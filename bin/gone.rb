#!/home/figshare/ruby/bin/ruby
require 'wikk_configuration'
require_relative '../rlib/dropbox.rb'
require_relative '../rlib/uoa.rb' #Localized front ends to dropbox and ldap calls.
require_relative '../rlib/ldap.rb'

TRACE=false #Dump output of calls to dropbox

conf_file = "#{File.expand_path(File.dirname(__FILE__))}/../conf/auth.json"
@conf = WIKK::Configuration.new(conf_file)

#Team information – Information about the team and aggregate usage data
@dbx_info = Dropbox.new(token: @conf.team_info_token) 

@ldap = UOA_LDAP.new(conf: @conf)

cache_all_team_members(trace: TRACE)
@team_member_map.each do |k,v|
  puts "Gone #{k} => #{v["email"]}" if ! @ldap.memberof?(user: k, group: 'nectar_access.eresearch')
end
puts
puts "Manually added Entries with no External_ID set!"
@partial_entries.each do |v|
  p v["email"]
end
