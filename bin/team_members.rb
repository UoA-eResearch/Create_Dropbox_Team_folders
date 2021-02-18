#!/usr/local/bin/ruby
require 'wikk_configuration'
require_relative '../rlib/dropbox.rb'
require_relative '../rlib/uoa.rb' #Localized front ends to dropbox and ldap calls.

DRYRUN=false #Run through actions, printing what would have been done, but don't execute them
TRACE=false #Dump output of calls to dropbox

conf_file = "#{File.expand_path(File.dirname(__FILE__))}/../conf/auth.json"
@conf = WIKK::Configuration.new(conf_file)

#Team information – Information about the team and aggregate usage data
@dbx_info = Dropbox.new(token: @conf.team_info_token) 

cache_all_team_members(trace: TRACE)
@team_member_map.each do |k,v|
  puts "#{k} => #{v["email"]} #{v["role"]}"
end
puts
puts "Manually added Entries with no External_ID set!"
@partial_entries.each do |v|
  p v["email"]
end

