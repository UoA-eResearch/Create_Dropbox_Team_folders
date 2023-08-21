#!/usr/local/bin/ruby
require 'time'
require 'wikk_configuration'
require_relative '../rlib/ldap.rb' # json to class with accessor methods
require_relative '../rlib/dropbox.rb' # json to class with accessor methods
require_relative '../rlib/uoa.rb' # Localized front ends to dropbox and ldap calls.

DRYRUN = false # Run through actions, printing what would have been done, but don't execute them
TRACE = false # Dump output of calls to dropbox

# Read configuration file and initialize connections
def init_connections
  conf_file = "#{__dir__}/../conf/auth.json"
  @conf = WIKK::Configuration.new(conf_file)

  @ldap = UOA_LDAP.new(conf: @conf)

  # Team member file access – Team information and auditing, plus the ability to perform any action as any team member
  @dbx_file = Dropbox.new(token: @conf.team_file_token)

  # Team member management – Team information, plus the ability to add, edit, and delete team members
  @dbx_mng = Dropbox.new(token: @conf.team_management_token)

  # Team information – Information about the team and aggregate usage data
  @dbx_info = Dropbox.new(token: @conf.team_info_token)

  # Team member file access – Team information and auditing, plus the ability to perform any action as any team member
  # In this case, impersonating an admin user to perform user based calls.
  # Replaces using an Admin's user_token, which no longer works.
  # @dbx_person = Dropbox.new(token: @conf.user_token, as_admin: true)
  @dbx_person = Dropbox.new(token: @conf.team_file_token, admin_id: @conf.admin_id)

  @licenses = @conf.licenses
end

# Do housekeeping, by ensuring all manually added people have their profile set correctly.
# Don't override the exceptions file, but do override any entries not in this file.
def update_existing_team_members_profile
  cache_all_team_members(trace: TRACE)

  # These entries don't have all their fields set, so were manually entered.
  # Adding an @aucklanduni user manually, when they already exist with their staff email, will log an exception.
  @partial_entries.each do |v|
    puts "Notice: Manually updating user profile for #{v['email']} from UoA LDAP"
    begin
      update_team_users_profiles(email: v['email'])
    rescue StandardError => e
      warn "Error: #{e}"
    end
  end

  # Reload the team members, if we modified any of them.
  cache_all_team_members(trace: TRACE) if @partial_entries.length != 0
end

# Reads list of research groups using dropbox (currently from a json file, but later will be from research project DB)
# Adds new team members to dropbox
# Creates and populates or updates existing dropbox rw and ro groups for each research project
# Creates team folders, if they are missing
# Sets team folder ACLs using rw and ro groups just created
def process_each_research_project_using_dropbox
  research_projects = JSON.parse(File.read("#{__dir__}/../conf/projects.json"))

  research_projects.each do |rp|
    begin
      research_project = { research_code: rp['research_code'], team_folder: rp['team_folder'] }
      create_dropbox_team_folder_from_research_code(research_projects: research_project, dryrun: DRYRUN, trace: TRACE)
      puts
    rescue WIKK::WebBrowser::Error => _e
      # Ignore these and try the next group.
    end
  end
end

def existing_research_group?(groupname:)
  return @research_groups[groupname].nil?
end

def process_manual_groups(dryrun: DRYRUN, trace: TRACE)
  return if @manual_users.length == 0

  # Add in users from the exceptions file, if they don't already exist in dropbox.
  add_missing_members(members_arr: @manual_users.values, dryrun: dryrun, trace: trace)

  # Add users to the dropbox groups, as per exceptions.json
  @manual_groups.each do |groupname, members|
    next if existing_research_group?(groupname: groupname) # No manual overriding of LDAP research groups.

    begin
      email_address_list = []  # create a blank email list for this group
      members.each { |m| email_address_list << m['email'] } # add users emails to the group
      @failed_to_add.each { |email| email_address_list.delete(email) }
      # Do a diff, and add or remove users from the dropbox group.
      update_dropbox_group(group_name: groupname, email_list: email_address_list, dryrun: dryrun, trace: trace)
    rescue WIKK::WebBrowser::Error => _e
      # Ignore web errors, and continue.
    end
  end

  @manual_users.each do |upi, ldap_entry|
    if @team_member_map[upi].nil?
      warn "process_manual_groups: Unknown dropbox account, when changing role, for #{upi}"
    elsif @team_member_map[upi]['role'] != ldap_entry['role']
      if dryrun
        puts "Changing role of #{upi} to #{ldap_entry['role']}"
      else
        @dbx_mng.team_members_set_admin_permissions(team_member_id: @team_member_map[upi]['team_member_id'], role: ldap_entry['role'], trace: trace)
      end
    elsif dryrun
      puts "Role of #{upi} unchanged from #{ldap_entry['role']}"
    end
  end
end

# Reads conf/exceptions.json and processes the entries
# This file allows
# * manually adding of users, that would not be in any research project group
# * manual assignment of users to groups (non-research groups)
# * overriding the email address (Necessary, where there is an IDP email field mismatch with the AD mail field)
def init_exceptions
  @manual_groups['user_added_manually'] = [] # Create empty array for this default group, we add all exceptions too. This has no team folder.

  # e.g.   "rbur004": { "email": "", "role": "Team admin", "group": ["UoA Admins"], "note": "CeR Rob Burrowes", "expires": "9999-12-31"},
  @manual_entries = JSON.parse(File.read("#{__dir__}/../conf/exceptions.json"))
  @manual_entries.each do |upi, r|
    next if upi == 'comment'  # Skip the comment at the start.

    next unless Time.parse(r['expires']) > Time.now # Entry is still valid

    manual_email = r['email'].nil? || r['email'] == '' ? nil : r['email'].downcase
    new_user_entry = @ldap.get_ldap_user_attributies(upi: upi, attributes: { 'sn' => 'surname', 'givenname' => 'given_name', 'mail' => 'email', 'cn' => 'external_id' })
    new_user_entry['role'] = r['role']

    # Manually added users still need to be in the UoA AD to be in the UoA dropbox team.
    if new_user_entry.nil?
      warn "exception.json: #{upi} Need to have a UoA identity (user not found in AD)"
    else
      new_user_entry['email'] = manual_email unless manual_email.nil? # Replace LDAP email address, with our version.
      @manual_users[upi] = new_user_entry

      @manual_groups['user_added_manually'] << new_user_entry
      if r['group'].instance_of?(Array)
        r['group'].each do |g|
          @manual_groups[g] ||= [] # Create array, if it didn't already exist for this group
          @manual_groups[g] << new_user_entry
        end
      end
    end
  end
end

def init
  @manual_users = {}     # Users we in the exceptions.json file (still required to have a UoA account to use the UoA IDP)
  @manual_groups = {}    # Groups we are creating in dropbox. These shouldn't be a research projects group in the AD
  @research_project_users = {}  # We are going to collect the research project users {using a hash for easy lookup}
  @research_groups = {}         # We are going to collect all research group names (using a hash for easy lookup)
  @failed_to_add = []      # Collect any users we couldn't add to the Team, as we need to ensure we don't try to add them to any group.

  init_connections
  init_exceptions
end

init
update_existing_team_members_profile
process_each_research_project_using_dropbox
process_manual_groups
