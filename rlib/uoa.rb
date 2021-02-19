#Fetch group members from the UoA LDAP, and create a members array, and an email address array
# Nb. some email addresses not in @auckland or @aucklanduni, so generate an upi@aucklanduni address for them
# @param groupname [String] LDAP group name
# @return [Array<Hash>,Array<String>] Two arrays returned. First is individual's details, Second is just their email address
def fetch_group_and_email_addresses(groupname: )
  member_array = @ldap.get_ldap_group_members(groupname: groupname)
  #extract email addresses
  email_addresses = []
  member_array.each do |m| 
    m.email = m.email.downcase
    m.email = @manual_users[m.external_id].email unless @manual_users[m.external_id].nil? # Override email, if in exceptions
    
    if m.email =~ /^.+@auckland\.ac\.nz$/ || m.email =~ /^.+@aucklanduni\.ac\.nz$/
      email_addresses << m.email
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
  
  ['rw','ro','t'].each { |suffix| @research_groups["#{research_code}_#{suffix}.eresearch"] = true } #record the research groups
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
        puts "Error: In create_dropbox_team_folder_from_research_code(): Creating team folder failed."
        return
      end
    end
  else
    puts "Team Folder #{team_folder} exists"
  end

  puts "Checking if we should add members from LDAP group #{traverse_group}"
  p( member_array_t ) if dryrun || trace  #Debugging 
  
  failed_to_add = add_missing_members(members_arr: member_array_t, dryrun: dryrun, trace: trace)
  puts
  
  failed_to_add.each do |email|
    [email_addresses_rw, email_addresses_ro, email_addresses_t].each do |email_addresses|
      email_addresses.delete(email)
    end
  end
  
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

# add_missing_members check with dropbox, to see if the members exist
# If not, it adds the missing members to dropbox.
# For existing users, it validates the dropbox email address is correct, and changes it if necessary
# The users role is set the to 
# @param members_arr [Array] Each member is an OpenStruct LDAP record, for a user
# @return [Array] list of email addresses for users that we failed to add as members.
def add_missing_members(members_arr:, dryrun: false, trace: false)
  members_to_add = []
  failed_to_add = []
  
  #Look to see if the user is already a member, and if they are, check their email address is still valid.
  members_arr.each do |m|
    @research_project_users[m.external_id] = true  # record every user we encounter
    
    if !member_exists?(member: m)
      members_to_add << m
      update_team_member_map(member: m) #Adds a placeholder, so we don't add this user again, while processing a later research group.
    elsif email_address_changed?(member: m)
      if @team_member_email_map[m.email]
        puts "WARNING Email address conflict. A Dropbox account '#{m.email}' already exists, so we can change the email of '#{@team_member_map[m.external_id]["email"]}'"
      else
        puts "WARNING: Email address changed from #{@team_member_map[m.external_id]["email"]} to #{m.email}"
        @dbx_mng.team_members_set_profile(email: @team_member_map[m.external_id]["email"],  new_email: m.email, trace: trace) unless dryrun
        update_team_member_map(member: m) #updates the entry in the cached copy of team members, so we don't try and change it again.
      end
    end
  end

  puts "Adding members"
  p( members_to_add )

  if  members_to_add.length > 0 && !dryrun
    begin
      #Doesn't matter if the users already exists, but we have culled these anyway, as we have to check for changed emails.
      response = @dbx_mng.team_add_members(members_details: members_to_add, send_welcome: true, trace: trace)
      
      #Response will have those who didn't get added due to an error. We can't add these to a group, so we remove these bad ones.
      response.each { |user_email| failed_to_add << user_email }
    rescue WebBrowser::Error => e
    end
  end
  
  return failed_to_add
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

#Prefetch all team members from Dropbox, so we can check if a user already exists.
#This will allow us to spot cases of a user's email address changing, without having to get a 409 error.
# @param trace [Boolean] Dump raw results from Dropbox API
def cache_all_team_members(trace: false)
  @partial_entries = []
  @team_member_map = {}
  @team_member_email_map = {} #Shouldn't need this, but manual entries through the web interface can cause conflicts.
  @dbx_info.team_list(trace: trace) do |tf|
    upi = tf["profile"]["external_id"]
    if upi != nil && upi != ''
      @team_member_email_map[tf["profile"]['email']] = upi
      tf["profile"]['role'] = tf["role"][".tag"] # Shift the role, into the profile
      @team_member_map[upi] = tf["profile"]
    else # These are problematic, as they can conflict with automatically added ones.
      tf["profile"]['role'] = tf["role"][".tag"] # Shift the role, into the profile
      @partial_entries << tf["profile"] 
      @team_member_email_map[tf["profile"]['email']] = '' # Unknown UPI, or more likely, a student and staff email conflict.
    end
  end
end

def update_team_member_map(member:)
  @team_member_map[member.external_id] ||= {} #Create entry, if it doesn't exist
  
  #Update parameters we care about.
  @team_member_map[member.external_id]["email"] = member.email
  @team_member_map[member.external_id]["external_id"] = member.external_id
  @team_member_map[member.external_id]["name"] ||= {}
  @team_member_map[member.external_id]["name"]["given_name"] = member.given_name
  @team_member_map[member.external_id]["name"]["surname"] = member.surname
  @team_member_email_map[member.email] = member.external_id # Reverse lookup, by email address.
end

#Check to see if this members email address from the UOA LDAP is the same as the dropbox one.
#Relies on having the DropBox external_id set to the UOA Login
# @param member [OpenStruct] Struct created from LDAP fetch of users attributes
def email_address_changed?(member:)
  cache_all_team_members if @team_member_map == nil
  return member_exists?(member: member) && @team_member_map[member.external_id]["email"] != member.email
end

#Check to see if this members is already in DropBox.
#Relies on having the DropBox external_id set to the UOA Login
# @param member [OpenStruct] Struct created from LDAP fetch of users attributes
def member_exists?(member:)
  cache_all_team_members if @team_member_map == nil
  return @team_member_map[member.external_id] != nil
end

#set the Dropbox user profile attributes to those in the UoA LDAP
# @param email [String] Email address used for identity of the user in DropBox.
def update_team_users_profiles(email:)
  if email =~ /^.+@aucklanduni.ac.nz/   #UoA gmail account, so we know the UPI.
    attr = @ldap.get_ldap_user_attributies(upi: email.gsub(/@aucklanduni.ac.nz/,''), attributes: {'sn'=>'surname', 'givenname'=>'given_name', 'mail'=>'email', 'cn'=>'external_id'})
  else #We don't know the UPI, so we need to lookup by email address. 
      attr = @ldap.get_ldap_user_attributies_by_email(email: email, attributes: {'sn'=>'surname', 'givenname'=>'given_name', 'mail'=>'email', 'cn'=>'external_id'})
  end
  
  if attr != nil
    attr.email = @manual_users[attr.external_id].email unless @manual_users[attr.external_id].nil? # Override email, if in exceptions
    @dbx_mng.team_members_set_profile(email: attr.email, given_name: attr.given_name, surname: attr.surname, new_external_id: attr.external_id, trace: false)
  else
    warn "Error: In update_team_users_profiles(): No LDAP entry for #{email}"
  end
end
