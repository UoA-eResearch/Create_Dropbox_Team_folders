#!/usr/local/bin/ruby
require 'wikk_configuration'
require_relative '../rlib/dropbox.rb'
require_relative '../rlib/uoa.rb' # Localized front ends to dropbox and ldap calls.
require_relative '../rlib/ldap.rb'
require 'time'

TRACE = false # Dump output of calls to dropbox
DRYRUN = false # Run through actions, printing what would have been done, but don't execute them

def init
  conf_file = "#{__dir__}/../conf/auth.json"
  @conf = WIKK::Configuration.new(conf_file)

  # Team information – Information about the team and aggregate usage data
  @dbx_info = Dropbox.new(token: @conf.team_info_token)
  @dbx_mng = Dropbox.new(token: @conf.team_management_token)

  @ldap = UOA_LDAP.new(conf: @conf)

  @counters = {}
  cache_all_team_members(trace: TRACE)
  record_research_groups_and_users
end

def record_research_groups_and_users
  @research_groups = {}         # We are going to collect all research group names (using a hash for easy lookup)
  @research_project_users = {}  # We are going to collect the research project users {using a hash for easy lookup}
  @manual_users = {}     # Users we in the exceptions.json file (still required to have a UoA account to use the UoA IDP)
  @manual_groups = {}    # Groups we are creating in dropbox. These shouldn't be a research projects group in the AD

  research_projects = JSON.parse(File.read("#{__dir__}/../conf/projects.json"))
  research_projects.each do |rp|
    [ 'rw', 'ro' ].each do |suffix|
      group_name = "#{rp['research_code']}_#{suffix}.eresearch"
      @research_groups[group_name] = true  # record the research groups
      member_array, _email_addresses = fetch_group_and_email_addresses(groupname: group_name)
      next if member_array.nil?

      member_array.each do |m|
        @research_project_users[m['external_id']] = true  # record every user we encounter
      end
    end
  end

  manual_entries = JSON.parse(File.read("#{__dir__}/../conf/exceptions.json"))
  manual_entries.each do |upi, _r|
    @research_project_users[upi] = true
  end
end

def check_user_membership
  output = [] # lines of output, so we can sort them.

  # enumerate all profiles.
  now = Time.now
  @team_member_map.each do |upi, profile|
    deleted = false
    in_out = @research_project_users[upi].nil? ? 'No' : 'In'
    invited = profile['status']['.tag'] == 'invited'
    if invited
      invited_on = Time.parse(profile['invited_on'])
      category = 'Invited'
      if (now - invited_on) / 86400 > 93 # Added over 3 months ago.
        @counters["#{category} Old #{in_out} Proj"] ||= 0
        @counters["#{category} Old #{in_out} Proj"] += 1
        if in_out == 'No'
          puts "Deleting #{upi} #{profile['email']}: old invite, with no project"
          # Can't keep an invited, but not accepted account.
          @dbx_mng.team_remove_member(team_member_id: profile['team_member_id'], keep_account: false)
          deleted = true
        end
      else # Recent additions
        @counters["#{category} #{in_out} Proj"] ||= 0
        @counters["#{category} #{in_out} Proj"] += 1
      end
    end

    if @ldap.memberof?(user: upi, group: 'dropbox_access.eresearch')
      category = 'Staff/PhD'
      output << "#{category} #{in_out} Proj   #{upi} => #{profile['email']} #{profile['name']['display_name']}"
      @counters["#{category} #{in_out} Proj"] ||= 0
      @counters["#{category} #{in_out} Proj"] += 1
    else
      category = if @ldap.memberof?(user: upi, group: 'Enrolled.now')
                   # Already captured PhD above, so this is either Masters or below
                   @ldap.memberof?(user: upi, group: 'Thesis-PhD.ec') ? 'Masters' : 'Student'
                 elsif @ldap.memberof?(user: upi, group: 'academic_emp.psrwi')
                   # We already captured Full time and fixed term, so this must be a Casual
                   'Casual Academic'
                 elsif @ldap.memberof?(user: upi, group: 'professional_casual_emp.psrwi')
                   # We already captured Full time and fixed term, so this must be a Casual
                   'Casual Professional'
                 elsif @ldap.memberof?(user: upi, group: 'ExternalCollaborators.psrwi')
                   # Visitors get captured as staff
                   'External Collaborator'
                 elsif @ldap.memberof?(user: upi, group: 'Contractor.psrwi')
                   'Contractor'
                 else
                   if in_out == 'No' && !deleted
                     puts "Disconnecting #{upi} #{profile['email']}: No affiliation, with no project"
                     # Can't keep an invited, but not accepted account.
                     @dbx_mng.team_remove_member(team_member_id: profile['team_member_id'], keep_account: true)
                   end
                   'No affiliation'
                 end
      @counters["#{category} #{in_out} Proj"] ||= 0
      @counters["#{category} #{in_out} Proj"] += 1
      output << "#{category} #{in_out} Proj  #{upi} => #{profile['email']}} #{profile['name']['display_name']}"
    end
  end
  output.sort.each { |l| puts l }
  puts

  puts 'Manually added Entries with no External_ID set!'
  @partial_entries.each do |v|
    p v['email']
  end
end

def print_team_stats
  # team_info_record = @dbx_info.team_info
  team_info_record = @dbx_info.team_info
  puts <<~TXT
    Max Licenses:  #{team_info_record['num_licensed_users']} (Really 2,215)
    Used Licenses: #{team_info_record['num_used_licenses']}
  TXT
end

init

check_user_membership
puts
print_team_stats
puts

@counters.sort.each do |k, v|
  puts "#{k}: #{v}"
end
