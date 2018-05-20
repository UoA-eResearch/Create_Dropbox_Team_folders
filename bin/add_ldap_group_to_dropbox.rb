#!/usr/local/bin/ruby
require 'wikk_configuration'
require_relative '../rlib/ldap.rb' #json to class with accessor methods
require_relative '../rlib/dropbox.rb' #json to class with accessor methods
require_relative '../rlib/uoa.rb' #Localized front ends to dropbox and ldap calls.

conf_file = "#{File.expand_path(File.dirname(__FILE__))}/../conf/auth.json"
@conf = WIKK::Configuration.new(conf_file)
@ldap = UOA_LDAP.new(conf: @conf)
@dbx_file = Dropbox.new(token: @conf.team_file_token)
@dbx_mng = Dropbox.new(token: @conf.team_management_token)
@dbx_info = Dropbox.new(token: @conf.team_info_token)
@dbx_person = Dropbox.new(token: @conf.user_token)

research_projects = JSON.parse(File.read("#{File.expand_path(File.dirname(__FILE__))}/../conf/projects.json"))

research_projects.each do |rp|
  research_project = {:research_code => rp["research_code"], :team_folder => rp["team_folder"]}
  create_dropbox_team_folder_from_research_code(research_projects: research_project, debug: false)
  puts
end



