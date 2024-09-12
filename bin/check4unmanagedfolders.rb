#!/home/dropbox/ruby3/bin/ruby
require 'time'
require 'wikk_configuration'
require_relative '../rlib/ldap.rb' # json to class with accessor methods
require_relative '../rlib/dropbox.rb' # json to class with accessor methods
require_relative '../rlib/uoa.rb' # Localized front ends to dropbox and ldap calls.

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

# Prefetch all team folder ids from Dropbox, so we can look up team folder IDs by team folder name
# @param trace [Boolean] Dump raw results from Dropbox API
def cache_all_active_team_folder_ids(trace: false)
  @team_folder_id_map = {}
  @dbx_file.team_folder_list(trace: trace) do |tf|
    @team_folder_id_map[tf['name']] = tf['team_folder_id'] if tf['status']['.tag'] == 'active'
  end
end

def load_projects
  @research_projects = JSON.parse(File.read("#{__dir__}/../conf/projects.json"))
  @research_project_research_code_map = {}

  @research_projects.each do |rp|
    @research_project_research_code_map[rp['team_folder']] = rp['research_code']
  end
end

def check_for_unmanaged_folders
  @team_folder_id_map.each do |name, _id|
    warn "Unmanaged Team Folder #{name}" if @research_project_research_code_map[name].nil?
  end
end

init
cache_all_active_team_folder_ids
load_projects
check_for_unmanaged_folders
