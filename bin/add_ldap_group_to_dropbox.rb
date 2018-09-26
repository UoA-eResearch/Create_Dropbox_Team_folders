#!/usr/local/bin/ruby
require 'wikk_configuration'
require_relative '../rlib/ldap.rb' #json to class with accessor methods
require_relative '../rlib/dropbox.rb' #json to class with accessor methods
require_relative '../rlib/uoa.rb' #Localized front ends to dropbox and ldap calls.

DRYRUN=false #Run through actions, printing what would have been done, but don't execute them
TRACE=false #Dump output of calls to dropbox

conf_file = "#{File.expand_path(File.dirname(__FILE__))}/../conf/auth.json"
@conf = WIKK::Configuration.new(conf_file)

@ldap = UOA_LDAP.new(conf: @conf)

#Team member file access – Team information and auditing, plus the ability to perform any action as any team member
@dbx_file = Dropbox.new(token: @conf.team_file_token)

#Team member management – Team information, plus the ability to add, edit, and delete team members
@dbx_mng = Dropbox.new(token: @conf.team_management_token)

#Team information – Information about the team and aggregate usage data
@dbx_info = Dropbox.new(token: @conf.team_info_token) 

#Team member file access – Team information and auditing, plus the ability to perform any action as any team member
#In this case, impersonating an admin user to perform user based calls. 
#Replaces using an Admin's user_token, which no longer works. 
#@dbx_person = Dropbox.new(token: @conf.user_token, as_admin: true)
@dbx_person = Dropbox.new(token: @conf.team_file_token, admin_id: @conf.admin_id)

#Do housekeeping, by ensuring all manually added people have their profile set correctly.
cache_all_team_members(trace: TRACE)
@partial_entries.each do |v|
  puts "Notice: Manually added user #{v["email"]} profile updated from LDAP"
  update_team_users_profiles(email: v["email"])
end

#Reload the team members, if we modified any of them.
cache_all_team_members(trace: TRACE) if @partial_entries.length != 0


research_projects = JSON.parse(File.read("#{File.expand_path(File.dirname(__FILE__))}/../conf/projects.json"))

research_projects.each do |rp|
  begin
    research_project = {:research_code => rp["research_code"], :team_folder => rp["team_folder"]}
    create_dropbox_team_folder_from_research_code(research_projects: research_project, dryrun: DRYRUN, trace: TRACE)
    puts
  rescue WebBrowser::Error => e
    #Ignore these and try the next group.
  end
end
