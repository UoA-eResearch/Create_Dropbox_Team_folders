require 'wikk_configuration'
require_relative '../rlib/dropbox.rb'
require_relative '../rlib/uoa.rb' #Localized front ends to dropbox and ldap calls.
require_relative '../rlib/ldap.rb' #json to class with accessor methods

DRYRUN=false #Run through actions, printing what would have been done, but don't execute them
TRACE=false #Dump output of calls to dropbox

conf_file = "#{File.expand_path(File.dirname(__FILE__))}/../conf/auth.json"
@conf = WIKK::Configuration.new(conf_file)

#Team information – Information about the team and aggregate usage data
@dbx_info = Dropbox.new(token: @conf.team_info_token) 

#Team member management – Team information, plus the ability to add, edit, and delete team members
@dbx_mng = Dropbox.new(token: @conf.team_management_token)

#Init ldap connection
@ldap = UOA_LDAP.new(conf: @conf)

cache_all_team_members(trace: TRACE)
@partial_entries.each do |v|
  update_team_users_profiles(email: v["email"])
end

