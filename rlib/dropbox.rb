require_relative 'webbrowser.rb'
require 'json'
require 'pp'

class Dropbox
  
  DROPBOX_API_SERVER = 'api.dropboxapi.com'
  
  def initialize(token:)
    @auth_token = token
  end
  
  def self.connect(token:)
    self.new(token: token)
    yield
  end
        
  # Perform a dropbox API query, using the html API
  # @param query [String] the dropbox query
  # @param query_data [String] Json data sent with the query
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @return [Array<Hash>] Dropbox response is a JSON array, which we parse, and return as a Ruby Array.
  def dropbox_query(query:, query_data: '{}', trace: false)
    WebBrowser::https_session(host: DROPBOX_API_SERVER, verify_cert: false) do |wb|
      retry_count = 0
      begin
        r = wb.post_page(query: query, authorization: wb.bearer_authorization(token:@auth_token),  content_type: 'application/json', data: query_data)
        h = JSON.parse(r)
        puts JSON.pretty_generate(h) if trace
        return h
      rescue WebBrowser::Error => e
        puts "Error: #{e.class} #{e}"
        if e.web_return_code == 429 #Too Many Requests
          retry_count += 1
          sleep retry_count
          return dropbox_query(query: query, query_data: query_data, trace: trace, retry_count: retry_count) if retry_count <= 4
        end
      rescue StandardError=>e
        puts "Error: #{e.class} #{e}"
      end
    end
  end

  # Get all the members of our team
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each team member in the response Array
  def team_list(trace: false)
    r = dropbox_query(query: '2/team/members/list', trace: trace)
    r["members"].each do |g|
      yield g
    end
    while r["has_more"] 
      r = dropbox_query(query: '2/team/members/list/continue', query_data: "{\"cursor\":\"#{r["cursor"]}\"}", trace: trace)
      r["members"].each do |g|
        yield g
      end
    end
  end
  
  # Get all the groups for our team
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each group in the response Array
  def groups_list(trace: false)
    r = dropbox_query(query: '2/team/groups/list', trace: trace)
    r["groups"].each do |g|
      yield g
    end
    while r["has_more"] 
      r = dropbox_query(query: '2/team/groups/list/continue', query_data: "{\"cursor\":\"#{r["cursor"]}\"}", trace: trace)
      r["groups"].each do |g|
        yield g
      end
    end
  end
  
  #Find a group folders ID from its name (not something Dropbox API does)
  # @param group_name [String] 
  # @return group_id
  def group_id(group_name:, trace: false)
    groups_list(trace: trace) do |gf|
      if gf["group_name"] == group_name
        return gf["group_id"]
      end
    end
    return nil
  end
  

  # Get all the folders for our team
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each folders in the response Array
  def team_folder_list(trace: false)
    r = dropbox_query(query: '2/team/team_folder/list',trace: trace)
    r["team_folders"].each do |n|
      yield n
    end
    while r["has_more"] 
      r = dropbox_query(query: '2/team/team_folder/list/continue', query_data: "{\"cursor\":\"#{r["cursor"]}\"}", trace: trace)
      r["team_folders"].each do |n|
        yield n
      end
    end
  end
  
  #Create a team folder
  # @param folder [String] Folder name
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @return [Hash] result from dropbox
  def team_folder_create(folder:, trace: false)
    dropbox_query(query: '2/team/team_folder/create', query_data: "{\"name\":\"#{folder}\"}", trace: trace)
  end
  
  #Find a team folders ID from its name (not something Dropbox API does)
  # @param folder_name [String] 
  # @return team_folder_id
  def team_folder_id(folder_name:, trace: false)
    team_folder_list(trace: trace) do |tf|
      if tf["name"] == folder_name
        return tf["team_folder_id"]
      end
    end
    return nil
  end

  # Get all the name spaces for our teams.
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each namespace in the response Array
  def namespaces_list(trace: false)
    r = dropbox_query(query: '2/team/namespaces/list',trace: trace)
    r["namespaces"].each do |n|
      yield n
    end
    while r["has_more"] 
      r = dropbox_query(query: '2/team/groups/list/continue', query_data: "{\"cursor\":\"#{r["cursor"]}\"}", trace: trace)
      r["namespaces"].each do |n|
        yield n
      end
    end
  end

  # Get all the dropbox events for our team.
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each event in the response Array
  def get_events(trace: false)
    r = dropbox_query(query: '2/team_log/get_events',trace: trace)
    r["events"].each do |n|
      yield n
    end
    while r["has_more"] 
      r = dropbox_query(query: '2/team_log/get_events/continue', query_data: "{\"cursor\":\"#{r["cursor"]}\"}", trace: trace)
      r["events"].each do |n|
        yield n
      end
    end
  end

  # Add members to the team. It doesn't matter if the list includes people already in the team.
  # @param members_details [Array<Object>] Array of Objects with read attributes email, given_name, surname, external_id
  # @param send_welcome [Boolean] Have Dropbox send users an invite email, after they get added.
  # @param trace [Boolean] If true, then print result of the query to stdout
  def team_add_members(members_details:, send_welcome: true, trace: false ) #email:, given_name:, surname:, external_id: )
    #Limited to adding 20 members at a time, so create sub arrays of size 20 or less, and process each one.
    (0..members_details.length).step(20) do |i|
    	members_details_20 = members_details[i..i+19]
    	member_details_json = []
    	members_details_20.each do |m|
    	  if m != nil #Shouldn't ever get a nil
    	    member_details_json << "{  \"member_email\":\"#{m.email}\",\"member_given_name\":\"#{m.given_name}\",\"member_surname\":\"#{m.surname}\",\"member_external_id\":\"#{m.external_id}\",\"send_welcome_email\":#{send_welcome},\"role\":{\".tag\":\"member_only\"}}"
    	  end
    	end
      member_query = "{\"new_members\": [ #{member_details_json.join(',')} ]}"
      dropbox_query(query: '2/team/members/add', query_data: member_query, trace: trace)
    end
  end

  # Create a dropbox group, and sets the externalID to the groupName (as we can't do a query by groupName, only by group_name and group_external_id)
  # @param group_name [String] Dropbox group to create
  # @param trace [Boolean] If true, then print result of the query to stdout
  def group_create(group_name:, trace: false)
    group_query = "{\"group_name\":\"#{group_name}\",\"group_external_id\":\"#{group_name}\",\"group_management_type\":{\".tag\":\"company_managed\"}}"
    dropbox_query(query: '2/team/groups/create', query_data: group_query, trace: trace)
  end

  # Add members to a group. It doesn't matter if there are people in our list, that are already members of the group
  # @param group_id [String] Optional groupID to identify group. Need this, or the external_group_id
  # @param external_group_id [String] Optional external groupID to identify group. Need this, or the group_id
  # @param emails [Array<String>] List of email addresses, identifying the users we want to add to this dropbox group.
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @return [String] Json response from dropbox
  def group_add_members(external_group_id: nil, group_id: nil, emails:, trace: false)
    members = []
    emails.each do |e|
      members << "{\"user\":{\".tag\":\"email\",\"email\":\"#{e}\"},\"access_type\":{\".tag\":\"member\"}}"
    end
    if(group_id != nil)
      group_query = "{\"group\":{\".tag\":\"group_id\",\"group_id\":\"#{group_id}\"},\"members\":[#{members.join(',')}]}"
    else
      group_query = "{\"group\":{\".tag\":\"group_external_id\",\"group_external_id\":\"#{external_group_id}\"},\"members\":[#{members.join(',')}]}"
    end
    #puts group_query
    dropbox_query(query: '2/team/groups/members/add', query_data: group_query, trace: trace)
  end
  
  def group_remove_members(external_group_id: nil, group_id: nil, emails:, trace: false)
    members = []
    emails.each do |e|
      members << "{\".tag\":\"email\",\"email\":\"#{e}\"}"
    end
    if(group_id != nil)
      group_query = "{\"group\":{\".tag\":\"group_id\",\"group_id\":\"#{group_id}\"},\"users\":[#{members.join(',')}]}"
    else
      group_query = "{\"group\":{\".tag\":\"group_external_id\",\"group_external_id\":\"#{external_group_id}\"},\"users\":[#{members.join(',')}]}"
    end

    dropbox_query(query: '2/team/groups/members/remove', query_data: group_query, trace: trace)
  end
  
  # List the members in a Dropbox group
  # @param group_id [String] Optional groupID to identify group. Need this, or the external_group_id
  # @param external_group_id [String] Optional external groupID to identify group. Need this, or the group_id
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [String] Json string, with the attributes of each member in the group
  def group_members_list(external_group_id: nil, group_id: nil, trace: false)
    if group_id != nil
      group_query = "{\"group\":{\".tag\":\"group_id\",\"group_id\":\"#{group_id}\"}}"
    elsif external_group_id != nil
      group_query = "{\"group\":{\".tag\":\"group_external_id\",\"group_external_id\":\"#{external_group_id}\"}}"
    else 
      return nil
    end
    r = dropbox_query(query: '2/team/groups/members/list', query_data: group_query, trace: trace)
    r["members"].each do |m|
      yield m
    end
    while r["has_more"] 
      r = dropbox_query(query: '2/team/groups/members/list/continue', query_data: "{\"cursor\":\"#{r["cursor"]}\"}", trace: trace)
      r["members"].each do |m|
        yield m
      end
    end
  end
  
  # Get details on specified members.
  # @param members [Array<Object>] identify members by team_member_id | external_id | email
  # @param trace [Boolean] If true, then print result of the query to stdout
  def members_get_info(members: , trace: false)
    members_json = []
    members.each do |m|
      if m.team_member_id != nil
        members_json << "{\".tag\":\"team_member_id\",\"team_member_id\":\"#{m.team_member_id}\"}"
      elsif m.external_id != nil
        members_json << "{\".tag\":\"external_id\",\"external_id\":\"#{m.external_id}\"}"
      elsif m.email != nil
        members_json << "{\".tag\":\"email\",\"email\":\"#{m.email}\"}"
      end
    end
    dropbox_query(query: '2/team/members/get_info', query_data: "{\"members\":[#{members_json.join(',')}]}", trace: trace)
  end
  
  # Get info on specified groups
  # @param group_ids [Array<String>] the group ids of the groups we want information on
  # @param external_group_ids [Array<String>] the external group ids of the groups we want information on  
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @return [Array] Result per group specified by external_group_ids, or by group_ids
  def group_get_info(external_group_ids: nil, group_ids: nil, trace: false)
    if group_ids != nil
      group_query = "{\".tag\":\"group_ids\",\"group_ids\":[\"#{group_ids.join('","')}\"]}"
    elsif external_group_ids != nil
      group_query = "{\".tag\":\"group_external_ids\",\"group_external_ids\":[\"#{external_group_ids.join('","')}\"]}"
    else 
      return nil
    end
    dropbox_query(query: '2/team/groups/get_info', query_data: group_query, trace: trace)
  end
  
  def list_folder_members(folder_id: , trace: false)
    r = dropbox_query(query: '2/sharing/list_folder_members', query_data: "{\"shared_folder_id\":\"#{folder_id}\"}", trace: trace) 
    h = { "users" => r["users"], "groups" => r["groups"], "invitees" => r["invitees"] }
    yield h
    #Needs loop if too many users or groups 
    while r["cursor"]
      r = dropbox_query(query: '2/sharing/list_folder_members/continue', query_data: "{\"cursor\":\"#{r["cursor"]}\"}", trace: trace) 
      h = { "users" => r["users"], "groups" => r["groups"], "invitees" => r["invitees"] }
      yield h
    end
  end
  
  # Adds group ACL to folder
  # @param folder_id [String] Dropbox folder_id
  # @param group_id [String] Dropbox group_id
  # @param access_role [String] "editor" by default. "viewer" for read only access
  # @param trace [Boolean] If true, then print result of the query to stdout
  def add_group_folder_member(folder_id:, group_id:, access_role: "editor", custom_message: nil, trace: false)
    query_data = "{\"shared_folder_id\":\"#{folder_id}\",\"members\":[{\"member\":{\".tag\":\"dropbox_id\",\"dropbox_id\":\"#{group_id}\"},\"access_level\":{\".tag\":\"#{access_role}\"}}],\"custom_message\":#{ custom_message == nil ? "null" : "\"#{custom_message}\"" },\"quiet\":true}"
    
    dropbox_query(query: '2/sharing/add_folder_member', query_data: query_data, trace: trace) 
  end
    
  # Adds a user ACL to folder
  # @param folder_id [String] Dropbox folder_id
  # @param email [String] Optional: Users UoA email 
  # @param user_id [String] Optional: Dropbox user_id
  # @param access_role [String] "editor" by default. "viewer" for read only access
  # @param trace [Boolean] If true, then print result of the query to stdout
  def add_user_folder_member(folder_id:, user_id: nil, email: nil, access_role: "editor", custom_message: nil, trace: false)
    if email != nil
      query_data = "{\"shared_folder_id\":\"#{folder_id}\",\"members\":[{\"member\":{\".tag\":\"email\",\"email\":\"#{email}\"},\"access_level\":{\".tag\":\"#{access_role}\"}}],\"custom_message\":#{ custom_message == nil ? "null" : "\"#{custom_message}\"" },\"quiet\":false}"
    elsif user_id != nil
      query_data = "{\"shared_folder_id\":\"#{folder_id}\",\"members\":[{\"member\":{\".tag\":\"dropbox_id\",\"dropbox_id\":\"#{user_id}\"},\"access_level\":{\".tag\":\"#{access_role}\"}}],\"custom_message\":#{ custom_message == nil ? "null" : "\"#{custom_message}\"" },\"quiet\":true}"
    end
    
    dropbox_query(query: '2/sharing/add_folder_member', query_data: query_data, trace: trace) 
  end
  
  def team_members_set_profile(team_member_id: nil, email: nil, external_id: nil, given_name: nil, surname: nil, new_external_id: nil, new_email: nil, trace: false)
    #2/team/members/set_profile
    if email != nil
      id = "{\".tag\":\"email\",\"email\":\"#{email}\"}" 
    elsif team_member_id != nil
      id = "{\".tag\":\"team_member_id\",\"team_member_id\":\"#{team_member_id}\"}"
    elsif external_id != nil
      id = "{\".tag\":\"external_id\",\"external_id\":\"#{external_id}\"}"
    end
    query_data_a = ["{\"user\":#{id}"]
    query_data_a << "\"new_external_id\":\"#{new_external_id}\"" if new_external_id
    query_data_a << "\"new_given_name\":\"#{given_name}\"" if given_name
    query_data_a << "\"new_surname\":\"#{surname}\"" if surname
    query_data_a << "\"new_email\":\"#{new_email}\"" if new_email
    
    if id != nil && query_data_a.length > 1
      puts query_data_a.join(',')
      dropbox_query(query: '2/team/members/set_profile', query_data: query_data_a.join(',') + '}', trace: trace) 
    end
  end
end
