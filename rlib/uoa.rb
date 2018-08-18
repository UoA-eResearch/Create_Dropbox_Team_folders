#Fetch group members from the UoA LDAP, and create a members array, and an email address array
# Nb. some email addresses not in @auckland or @aucklanduni, so generate an upi@aucklanduni address for them
# @param groupname [String] LDAP group name
# @return [Array<Hash>,Array<String>] Two arrays returned. First is individual's details, Second is just their email address
def fetch_group_and_email_addresses(groupname: )
  member_array = @ldap.get_ldap_group_members(groupname: groupname)
  #extract email addresses
  email_addresses = []
  member_array.each do |m| 
    email_address = m.email.downcase
    if email_address =~ /^.+@auckland\.ac\.nz$/ || email_address =~ /^.+@aucklanduni\.ac\.nz$/
      email_addresses << email_address
    else
      puts "Non-UoA Email Address: #{m.external_id} #{m.email} #{m.surname} #{m.given_name}. Using #{m.external_id}@aucklanduni.ac.nz"
      aucklanduni_email = "#{m.external_id}@aucklanduni.ac.nz".downcase
      email_addresses << aucklanduni_email
      m.email = aucklanduni_email
    end
  end
  return member_array, email_addresses
end

#update a dropbox team group using the email list of group members, creating the group if it didn't exist
# @param group_name [String] Identifies the group
# @param email_list [Array<String>] Email addresses of all the members
# @param dryrun [Boolean] Print, but Don't actually execute commands that would change Dropbox
# @param trace [Boolean] Dump raw results from Dropbox API
# @return [String] Dropbox team group_id
def update_dropbox_group(group_name:, email_list:, dryrun: false, trace: false)
  puts "update_dropbox_group #{group_name}"
  if dryrun || trace
    puts "Members should be #{email_list}"
    p email_list
  end
  current_members_email = []
  if (group_id = get_group_id(group_name: group_name, trace: trace) ) == nil
    puts "Creating Group '#{group_name}'"
    if !dryrun
      r = @dbx_mng.group_create(group_name: group_name, trace: trace)
      group_id = r["group_id"]
    end
  else
    puts "Group '#{group_name}' exists. Using existing group"
    @dbx_info.group_members_list(group_id: group_id, trace: trace) do |r|
      current_members_email << r["profile"]["email"]
    end
  end
  add_these_users = []
  email_list.each do |e|   
    if ! current_members_email.include?(e) #New Member not current Dropbox group
      add_these_users << e
    end
  end
  remove_these_users = []
  current_members_email.each do |e|
    if ! email_list.include?(e) #Member not in new email list
      remove_these_users << e
    end
  end
  
  begin
    puts "Adding these users to Group '#{group_name}'"
    p add_these_users
    @dbx_mng.group_add_members(group_id: group_id, emails: add_these_users, trace: trace) if add_these_users.length > 0 && !dryrun
    puts
  rescue WebBrowser::Error => e
    #Ignore, as reported previously
  end
  
  begin
    puts "Removing these users from Group '#{group_name}'"
    p remove_these_users
    @dbx_mng.group_remove_members(group_id: group_id, emails: remove_these_users, trace: trace) if remove_these_users.length > 0  && !dryrun
    puts
  rescue WebBrowser::Error => e
    #Ignore, as reported previously
  end
  
  return group_id
end

# create_dropbox_team_folder_from_research_code, and associated RW and RO ACL groups.
# @param research_projects [Array<Hash>] Each Array member defines a research project we need to process {:research_code => 'x', :team_folder => 'x'}
# @param dryrun [Boolean] Optional dryrun flag. If true, outputs what would happen, but doesn't do anything.
# @param trace [Boolean] Dump raw results from Dropbox API
def create_dropbox_team_folder_from_research_code(research_projects: , dryrun: false, trace: false)
  research_code = research_projects[:research_code]
  team_folder = research_projects[:team_folder]
  rw_group = research_code + '_rw' + '.eresearch'
  ro_group = research_code + '_ro' + '.eresearch'
  traverse_group = research_code + '_t' + '.eresearch'

 # member_array_t, email_addresses_t = fetch_group_and_email_addresses(groupname: traverse_group) #no always correct, so ignoring.
  member_array_t = []
  email_addresses_t = []
  member_array_rw, email_addresses_rw = fetch_group_and_email_addresses(groupname: rw_group)
  member_array_ro, email_addresses_ro = fetch_group_and_email_addresses(groupname: ro_group)

  if member_array_t.length == 0 && (member_array_rw.length != 0 || member_array_ro.length != 0)
    member_array_t = member_array_rw
    email_addresses_t = email_addresses_rw
    email_addresses_ro.each_with_index do |e, i|
      if ! email_addresses_t.include?(e)
        member_array_t << member_array_ro[i]
        email_addresses_t << e
      end
    end
  end
  
  if (team_folder_id = get_team_folder_id(folder_name: team_folder, trace: trace)) == nil
    puts "Creating Team Folder #{team_folder}"
    if !dryrun
      begin
        r = @dbx_file.team_folder_create(folder: team_folder, trace: trace) #Gives conflict error if the team folder already exists
        team_folder_id = r["team_folder_id"]
      rescue WebBrowser::Error => e
        puts "Creating team folder failed."
        return
      end
    end
  else
    puts "Team Folder #{team_folder} exists"
  end

  puts "Adding members from LDAP group #{traverse_group}"
  p( member_array_t ) if dryrun || trace
  if  member_array_t.length > 0 && !dryrun
    begin
      response = @dbx_mng.team_add_members(members_details: member_array_t, send_welcome: true, trace: trace) #Doesn't matter if the users already exists
      response.each do |user_email|
        email_addresses_rw.delete(user_email)
        email_addresses_ro.delete(user_email)
        email_addresses_t.delete(user_email)
      end
    rescue WebBrowser::Error => e
    end
  end
  puts

  begin
    group_id = update_dropbox_group(group_name: rw_group, email_list: email_addresses_rw, dryrun: dryrun, trace: trace)
    @dbx_person.add_group_folder_member(folder_id: team_folder_id, group_id: group_id, access_role: "editor", trace: trace) if !dryrun
  rescue WebBrowser::Error => e
  end

  begin
    group_id = update_dropbox_group(group_name: ro_group, email_list: email_addresses_ro, dryrun: dryrun, trace: trace)
    @dbx_person.add_group_folder_member(folder_id: team_folder_id, group_id: group_id, access_role: "viewer", trace: trace) if !dryrun
  rescue WebBrowser::Error => e
  end
end

#Prefetch all group ids from Dropbox, so we can look up group IDs by group name
# @param trace [Boolean] Dump raw results from Dropbox API
def cache_all_group_ids(trace: false)
  @group_id_map = {}
  @dbx_info.groups_list(trace: trace) do |gf|
    @group_id_map[gf["group_name"]] = gf["group_id"]
  end
end

#Map group name to group ID, as all dropbox calls are by group ID.
# @param group_name [String] Dropbox group name
# @param trace [Boolean] Dump raw results from Dropbox API
def get_group_id(group_name:, trace: false)
  cache_all_group_ids(trace: trace) if @group_id_map == nil
  return @group_id_map[group_name]
end

#Prefetch all team folder ids from Dropbox, so we can look up team folder IDs by team folder name
# @param trace [Boolean] Dump raw results from Dropbox API
def cache_all_team_folder_ids(trace: false)
  @team_folder_id_map = {}
  @dbx_file.team_folder_list(trace: trace) do |tf|
    @team_folder_id_map[tf["name"]] = tf["team_folder_id"]
  end
end

#Map team folder name to team folder ID, as all dropbox calls are by team folder ID.
# @param folder_name [String] Dropbox team folder name
# @param trace [Boolean] Dump raw results from Dropbox API
def get_team_folder_id(folder_name:, trace: false)
  cache_all_team_folder_ids(trace: trace) if @team_folder_id_map == nil
  return @team_folder_id_map[folder_name]
end

