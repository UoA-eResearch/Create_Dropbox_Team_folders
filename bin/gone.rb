#!/home/figshare/ruby/bin/ruby
require 'wikk_configuration'
require_relative '../rlib/dropbox.rb'
require_relative '../rlib/uoa.rb' #Localized front ends to dropbox and ldap calls.
require_relative '../rlib/ldap.rb'

TRACE=false #Dump output of calls to dropbox


def init
  conf_file = "#{File.expand_path(File.dirname(__FILE__))}/../conf/auth.json"
  @conf = WIKK::Configuration.new(conf_file)
  
  #Team information – Information about the team and aggregate usage data
  @dbx_info = Dropbox.new(token: @conf.team_info_token) 
  @ldap = UOA_LDAP.new(conf: @conf)
end

def record_research_groups_and_users
  @research_groups = {}         # We are going to collect all research group names (using a hash for easy lookup)
  @research_project_users = {}  # We are going to collect the research project users {using a hash for easy lookup}
  @manual_users = {}     # Users we in the exceptions.json file (still required to have a UoA account to use the UoA IDP)
  @manual_groups = {}    # Groups we are creating in dropbox. These shouldn't be a research projects group in the AD

  research_projects = JSON.parse(File.read("#{__dir__}/../conf/projects.json"))
  research_projects.each do |rp|
    ['rw','ro'].each do |suffix|
      group_name = "#{rp['research_code']}_#{suffix}.eresearch"
      @research_groups[group_name] = true  #record the research groups
      member_array, email_addresses = fetch_group_and_email_addresses(groupname: group_name)
      member_array.each do |m|
        @research_project_users[m.external_id] = true  # record every user we encounter
      end
    end
  end
  
  manual_entries = JSON.parse(File.read("#{__dir__}/../conf/exceptions.json"))
  manual_entries.each do |upi, r|
    @research_project_users[upi] = true
  end
  
end

init
cache_all_team_members(trace: TRACE)
record_research_groups_and_users

@team_member_map.each do |k,v|
  if @ldap.memberof?(user: k, group: 'nectar_access.eresearch') 
    if @research_project_users[k].nil?
      puts "UoA No Group   #{k} => #{v["email"]}"
    end
  else
    if @research_project_users[k].nil?
      puts "Gone No Group  #{k} => #{v["email"]}"
    else 
      puts "Gone In Group  #{k} => #{v["email"]}" 
    end 
  end
end
puts

puts "Manually added Entries with no External_ID set!"
@partial_entries.each do |v|
  p v["email"]
end
puts
