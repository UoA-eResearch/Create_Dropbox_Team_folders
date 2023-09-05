require 'wikk_webbrowser'
require 'json'
require 'pp'
require 'time'

# Encapsulate Dropbox API REST calls
class Dropbox
  DROPBOX_API_SERVER = 'api.dropboxapi.com'

  def initialize(token:, admin_id: nil)
    @auth_token = token
    @as_admin = admin_id != nil
    @admin_id = admin_id
  end

  def self.connect(token:)
    self.new(token: token)
    yield
  end

  # Perform a dropbox API query, using the html API
  # @param query [String] the dropbox query
  # @param query_data [String] Json data sent with the query
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @param retry_count [Integer] If we get a Dropbox "Too Many Requests", we sleep and retry for a max of 3 additional times
  # @return [Array<Hash>] Dropbox response is a JSON array, which we parse, and return as a Ruby Array.
  def dropbox_query(query:, query_data: '{}', trace: false, retry_count: 0, content_type: 'application/json')
    WIKK::WebBrowser.https_session(host: DROPBOX_API_SERVER, verify_cert: false) do |wb|
      begin
        r = wb.post_page( query: query,
                          authorization: wb.bearer_authorization(token: @auth_token),
                          content_type: content_type,
                          data: query_data,
                          extra_headers: @as_admin ? { 'Dropbox-API-Select-Admin' => @admin_id } : {}
                        )
        h = JSON.parse(r)
        puts JSON.pretty_generate(h) if trace
        return h
      rescue WIKK::WebBrowser::Error => e
        if e.web_return_code == 429 # Too Many Requests
          retry_count += 1
          sleep retry_count * 15
          if retry_count <= 4
            warn "Retry #{retry_count}: #{e.class} #{e}"
            return dropbox_query(query: query, query_data: query_data, trace: trace, retry_count: retry_count)
          else
            warn "Error (Aborting #{query} Try #{retry_count - 1}): #{e.class} #{e}"
            raise e
          end
        else
          warn "Error (Aborting #{query}): #{e.class} #{e}"
          raise e
        end
      rescue StandardError => e
        backtrace = e.backtrace[0].split(':')
        p backtrace
        warn "Error: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub(/'/, '\\\'')}".gsub(/\n/, ' ').gsub(/</, '&lt;').gsub(/>/, '&gt;')
      end
    end
  end

  # Get all the members of our team
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each team member in the response Array
  def team_list(trace: false, &block)
    r = dropbox_query(query: '2/team/members/list', trace: trace)
    r['members'].each(&block)
    while r['has_more']
      r = dropbox_query(query: '2/team/members/list/continue', query_data: { cursor: r['cursor'] }, trace: trace)
      r['members'].each(&block)
    end
  end

  # Get all the groups for our team
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each group in the response Array
  def groups_list(trace: false, &block)
    r = dropbox_query(query: '2/team/groups/list', trace: trace)
    r['groups'].each(&block)
    while r['has_more']
      r = dropbox_query(query: '2/team/groups/list/continue', query_data: { cursor: r['cursor'] }, trace: trace)
      r['groups'].each(&block)
    end
  end

  # Find a group folders ID from its name (not something Dropbox API does)
  # @param group_name [String]
  # @return group_id
  def group_id(group_name:, trace: false)
    groups_list(trace: trace) do |gf|
      if gf['group_name'] == group_name
        return gf['group_id']
      end
    end
    return nil
  end

  # Get all the folders for our team
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each folders in the response Array
  def team_folder_list(trace: false, limit: 1000, &block)
    r = dropbox_query(query: '2/team/team_folder/list', query_data: { limit: limit }, trace: trace)
    r['team_folders'].each(&block)
    while r['has_more']
      r = dropbox_query(query: '2/team/team_folder/list/continue', query_data: { cursor: r['cursor'] }, trace: trace)
      r['team_folders'].each(&block)
    end
  end

  # Get info for a list of team folder ids. Same output of team_folder_list, but not in an array.
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @param folder_ids [Array] of team folder ids
  # @yield [Hash] Hash for each folders in the response Array
  def team_folder_info(folder_ids:, trace: false)
    r = dropbox_query(query: '2/team/team_folder/get_info', query_data: { team_folder_ids: folder_ids }, trace: trace)
    # Return is just line separated hashes. Not surrounding [], so limit the call to one team id
    yield r
  end

  # Create a team folder
  # @param folder [String] Folder name
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @return [Hash] result from dropbox
  def team_folder_create(folder:, trace: false)
    dropbox_query(query: '2/team/team_folder/create', query_data: { name: folder }, trace: trace)
  end

  # Find a team folders ID from its name (not something Dropbox API does)
  # @param folder_name [String]
  # @return team_folder_id
  def team_folder_id(folder_name:, trace: false)
    team_folder_list(trace: trace) do |tf|
      if tf['name'] == folder_name
        return tf['team_folder_id']
      end
    end
    return nil
  end

  # Get all the name spaces for our teams.
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [Hash] Hash for each namespace in the response Array
  def namespaces_list(trace: false, &block)
    r = dropbox_query(query: '2/team/namespaces/list', trace: trace)
    r['namespaces'].each(&block)
    while r != nil && r['has_more']
      r = dropbox_query(query: '2/team/namespaces/list/continue', query_data: { cursor: r['cursor'] }, trace: trace)
      next unless r != nil

      r['namespaces'].each(&block)
    end
  end

  # Get all the dropbox events for our team.
  # Default to 31 days
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @param event [String] Filter events based on string (see Dropbox API)
  # @param limit [Integer] limit each pull of events to limit specified
  # @yield [Hash] Hash for each event in the response Array
  def get_events(event: 'file_operations', start_time: nil, end_time: nil, limit: 1000, trace: false, &block)
    end_time = Time.now if end_time.nil?
    start_time = (end_time - 3600 * 24 * 31) if start_time.nil?

    query = { category: event,
              time: { start_time: start_time.strftime('%Y-%m-%dT%H:%M:%SZ'), end_time: end_time.strftime('%Y-%m-%dT%H:%M:%SZ') },
              limit: limit
            }

    r = dropbox_query(query: '2/team_log/get_events',
                      query_data: query, trace: trace
    )
    r['events'].each(&block)
    while r['has_more']
      r = dropbox_query(query: '2/team_log/get_events/continue', query_data: { cursor: r['cursor'] }, trace: trace)
      r['events'].each(&block)
    end
  end

  # Add members to the team. It doesn't matter if the list includes people already in the team.
  # @param members_details [Array<Object>] Array of Objects with read attributes email, given_name, surname, external_id
  # @param send_welcome [Boolean] Have Dropbox send users an invite email, after they get added.
  # @param trace [Boolean] If true, then print result of the query to stdout
  def team_add_members(members_details:, send_welcome: true, trace: false ) # email:, given_name:, surname:, external_id: )
    # Limited to adding 20 members at a time, so create sub arrays of size 20 or less, and process each one.
    failed_to_add = [] # If we get an error adding one person, add them to this array and carry on.
    (0..members_details.length).step(20) do |i|
      members_details_20 = members_details[i..i + 19]
      member_details_json = []
      members_details_20.each do |m|
        next unless m != nil # Shouldn't ever get a nil

        member_details_json << {
          member_email: m['email'],
          member_given_name: m['given_name'],
          member_surname: m['surname'],
          member_external_id: m['external_id'],
          send_welcome_email: send_welcome,
          role: { '.tag' => member_only }
        }
      end
      member_query = { new_members: member_details_json }
      if (response = dropbox_query(query: '2/team/members/add', query_data: member_query, trace: trace)) != nil
        response['complete'].each do |user|
          if user['.tag'] == 'user_on_another_team' # Got a problem
            warn "Error: User #{user['user_on_another_team']} on another Team"
            failed_to_add << user['user_on_another_team']
          end
        end
      end
    end
    return failed_to_add
  end

  # Remove a member from the team
  # @param team_member_id [String] Users Dropbox member ID
  # @param keep_account [Boolean] If true, the account becomes a basic dropbox account
  # @param wipe_data [Boolean] Wipe the users data, unless we are keeping or transferring it
  # @param trace [Boolean] Debugging on
  def team_remove_member(team_member_id:, keep_account: false, wipe_data: true, transfer_to: nil, trace: nil)
    # Don't wipe the data if we are keeping the account (becomes a non-Team basic account)
    # Or if we are transferring the account to another dropbox account.
    # They still lose Team access, if the account is kept or transferred.
    wipe_data = false if keep_account || !transfer_to.nil?
    member = {
      user: { '.tag' => 'team_member_id', team_member_id: team_member_id },
      keep_account: keep_account,
      wipe_data: wipe_data,
      retain_team_shares: false # Don't retain access to team folders. They can always be invited back in.
    }

    # Unlikely, but we might want to transfer the account to a different ID
    members['transfer_dest_id'] = { '.tag' => 'team_member_id', team_member_id: transfer_to } unless transfer_to.nil?

    dropbox_query(query: '2/team/members/remove', query_data: member, trace: trace)
  end

  # Recover a deleted team member. THIS DOESN'T LOOK TO WORK!
  # @param team_member_id [String] Users Dropbox member ID
  # @param trace [Boolean] Debugging on
  def team_recover_member(team_member_id: nil, email: nil, external_id: nil, trace: nil)
    if ! team_member_id.nil?
      member = { 'user' => { '.tag' => 'team_member_id', 'team_member_id' => "#{team_member_id}" } }
    elsif ! email.nil?
      member = { 'user' => { '.tag' => 'email', 'email' => "#{email}" } }
    elsif ! external_id.nil?
      member = { 'user' => { '.tag' => 'external_id', 'external_id' => "#{external_id}" } }
    else
      raise 'team_recover_member() requires one of team_member_id, email or external_id'
    end
    dropbox_query(query: '2/team/members/recover', query_data: member, trace: trace)
  end

  # Change the users role
  # @param team_member_id [String] Dropbox member account to modify
  # @param role [String] One of ['team_admin', 'user_management_admin', 'support_admin', 'member_only']
  # @param trace [Boolean] If true, then print result of the query to stdout
  def team_members_set_admin_permissions(team_member_id:, role: 'member_only', trace: false )
    unless [ 'team_admin', 'user_management_admin', 'support_admin', 'member_only' ].include?(role)
      warn "Error: Unknown role team_members_set_admin_permissions(team_member_id: #{team_member_id}, role: #{role})"
      return
    end
    query_data = { user: { '.tag': 'team_member_id', team_member_id: team_member_id }, new_role: role }
    dropbox_query(query: '2/team/members/set_admin_permissions', query_data: query_data, trace: trace)
  end

  # Add a second email address to a member account.
  # Nb. This can't be their student email, if they are staff. Dropbox sees this as adding two different UoA users.
  # @param team_member_id [String] Dropbox member account to modify
  # @param secondary_email_addr [String] second email address
  # @param trace [Boolean] If true, then print result of the query to stdout
  def member_add_secondary_email(team_member_id:, secondary_email_addr:, trace: false)
    query_data = { new_secondary_emails: [ { user: { '.tag': 'team_member_id', team_member_id: team_member_id },
                                             secondary_emails: [ secondary_email_addr ]
                                           }
                                         ]
                 }
    dropbox_query(query: '2/team/members/secondary_emails/add', query_data: query_data, trace: trace)
  end

  # Create a dropbox group, and sets the externalID to the groupName (as we can't do a query by groupName, only by group_name and group_external_id)
  # @param group_name [String] Dropbox group to create
  # @param trace [Boolean] If true, then print result of the query to stdout
  def group_create(group_name:, trace: false)
    group_query = { group_name: group_name, group_external_id: group_name, group_management_type: { '.tag': 'company_managed' } }
    dropbox_query(query: '2/team/groups/create', query_data: group_query, trace: trace)
  end

  # Add members to a group. It doesn't matter if there are people in our list, that are already members of the group
  # @param group_id [String] Optional groupID to identify group. Need this, or the external_group_id
  # @param external_group_id [String] Optional external groupID to identify group. Need this, or the group_id
  # @param emails [Array<String>] List of email addresses, identifying the users we want to add to this dropbox group.
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @return [String] Json response from dropbox
  def group_add_members(emails:, external_group_id: nil, group_id: nil, trace: false)
    members = []
    emails.each do |e|
      members << { user: { '.tag': 'email', email: e }, access_type: { '.tag': 'member' } }
    end
    group_query = if group_id.nil?
                    { group: { '.tag': 'group_external_id', group_external_id: external_group_id }, members: members }
                  else
                    { group: { '.tag': 'group_id', group_id: group_id }, members: members }
                  end
    # puts group_query
    dropbox_query(query: '2/team/groups/members/add', query_data: group_query, trace: trace)
  end

  def group_remove_members(emails:, external_group_id: nil, group_id: nil, trace: false)
    members = []
    emails.each do |e|
      members << { '.tag': 'email', email: e }
    end
    group_query = if group_id.nil?
                    { group: { '.tag': 'group_external_id', group_external_id: external_group_id }, users: members }
                  else
                    { group: { '.tag': 'group_id', group_id: group_id }, users: members }
                  end

    dropbox_query(query: '2/team/groups/members/remove', query_data: group_query, trace: trace)
  end

  # List the members in a Dropbox group
  # @param group_id [String] Optional groupID to identify group. Need this, or the external_group_id
  # @param external_group_id [String] Optional external groupID to identify group. Need this, or the group_id
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @yield [String] Json string, with the attributes of each member in the group
  def group_members_list(external_group_id: nil, group_id: nil, trace: false, &block)
    if group_id != nil
      group_query = { group: { '.tag': 'group_id', group_id: group_id } }
    elsif external_group_id != nil
      group_query = { group: { '.tag': 'group_external_id', group_external_id: external_group_id } }
    else
      return nil
    end
    r = dropbox_query(query: '2/team/groups/members/list', query_data: group_query, trace: trace)
    r['members'].each(&block)
    while r['has_more']
      r = dropbox_query(query: '2/team/groups/members/list/continue', query_data: { cursor: r['cursor'] }, trace: trace)
      r['members'].each(&block)
    end
  end

  # Get details on specified members.
  # @param members [Array<Object>] identify members by team_member_id | external_id | email
  # @param trace [Boolean] If true, then print result of the query to stdout
  def members_get_info(members:, trace: false)
    members_json = []
    members.each do |m|
      if m['team_member_id'] != nil
        members_json << { '.tag': 'team_member_id', team_member_id: m['team_member_id'] }
      elsif m['external_id'] != nil
        members_json << { '.tag': 'external_id', external_id: m['external_id'] }
      elsif m['email'] != nil
        members_json << { '.tag': 'email', email: m['email'] }
      end
    end
    dropbox_query(query: '2/team/members/get_info', query_data: { members: members_json }, trace: trace)
  end

  # Get details on specified members.
  # @param members [Array<Object>] identify members by team_member_id | external_id | email
  # @param trace [Boolean] If true, then print result of the query to stdout
  # Returns structure different to the v1 version of this call.
  def members_get_info_v2(members:, trace: false)
    members_array = []
    members.each do |h|
      (tag, key) = h.to_a[0]
      case tag
      when 'team_member_id', 'email', 'external_id'
        members_array << { '.tag' => tag, "#{tag}" => "#{key}" }
      else
        raise 'members_get_info_v2() Only team_member_id, email or external_id can be used as indexes'
      end
    end
    dropbox_query(query: '2/team/members/get_info_v2', query_data: { 'members' => members_array }, trace: trace)
  end

  # Get info on specified groups
  # @param group_ids [Array<String>] the group ids of the groups we want information on
  # @param external_group_ids [Array<String>] the external group ids of the groups we want information on
  # @param trace [Boolean] If true, then print result of the query to stdout
  # @return [Array] Result per group specified by external_group_ids, or by group_ids
  def group_get_info(external_group_ids: nil, group_ids: nil, trace: false)
    if group_ids != nil
      group_query = { '.tag': 'group_ids', group_ids: group_ids }
    elsif external_group_ids != nil
      group_query = { '.tag': 'group_external_ids', group_external_ids: external_group_ids }
    else
      return nil
    end
    dropbox_query(query: '2/team/groups/get_info', query_data: group_query, trace: trace)
  end

  def list_folder_members(folder_id:, trace: false)
    r = dropbox_query(query: '2/sharing/list_folder_members', query_data: { shared_folder_id: folder_id }, trace: trace)
    h = { 'users' => r['users'], 'groups' => r['groups'], 'invitees' => r['invitees'] }
    yield h
    # Needs loop if too many users or groups
    while r['cursor']
      r = dropbox_query(query: '2/sharing/list_folder_members/continue', query_data: { cursor: r['cursor'] }, trace: trace)
      h = { 'users' => r['users'], 'groups' => r['groups'], 'invitees' => r['invitees'] }
      yield h
    end
  end

  # Adds group ACL to folder
  # @param folder_id [String] Dropbox folder_id
  # @param group_id [String] Dropbox group_id
  # @param access_role [String] "editor" by default. "viewer" for read only access
  # @param trace [Boolean] If true, then print result of the query to stdout
  def add_group_folder_member(folder_id:, group_id:, access_role: 'editor', custom_message: nil, trace: false)
    query_data = {
      shared_folder_id: folder_id,
      members: [ { member: { '.tag': 'dropbox_id', dropbox_id: group_id },
                   access_level: { '.tag': access_role }
                 }
      ],
      custom_message: custom_message.nil? ? 'null' : custom_message,
      quiet: true
    }

    dropbox_query(query: '2/sharing/add_folder_member', query_data: query_data, trace: trace)
  end

  # Adds a user ACL to folder
  # @param folder_id [String] Dropbox folder_id
  # @param email [String] Optional: Users UoA email
  # @param user_id [String] Optional: Dropbox user_id
  # @param access_role [String] "editor" by default. "viewer" for read only access
  # @param trace [Boolean] If true, then print result of the query to stdout
  def add_user_folder_member(folder_id:, user_id: nil, email: nil, access_role: 'editor', custom_message: nil, trace: false)
    if email != nil
      query_data = { shared_folder_id: folder_id,
                     members: [ { member: { '.tag': 'email', email: email },
                                  access_level: { '.tag': access_role }
                                }
                     ],
                     custom_message: custom_message.nil? ? 'null' : custom_message,
                     quiet: false
      }
    elsif user_id != nil
      query_data = { shared_folder_id: folder_id,
                     members: [ { member: { '.tag': 'dropbox_id', dropbox_id: user_id },
                                  access_level: { '.tag': access_role }
                                }
                     ],
                     custom_message: custom_message.nil? ? 'null' : custom_message,
                     quiet: true
                    }
    end

    dropbox_query(query: '2/sharing/add_folder_member', query_data: query_data, trace: trace)
  end

  def team_members_set_profile(team_member_id: nil, email: nil, external_id: nil, given_name: nil, surname: nil, new_external_id: nil, new_email: nil, trace: false)
    # 2/team/members/set_profile
    if email != nil
      id = { '.tag': 'email', email: email }
    elsif team_member_id != nil
      id = { '.tag': 'team_member_id', team_member_id: team_member_id }
    elsif external_id != nil
      id = { '.tag': 'external_id', external_id: external_id }
    end
    query_data_a = { user: id }
    query_data_a[:new_external_id] = new_external_id if new_external_id
    query_data_a[:new_given_name] = given_name if given_name
    query_data_a[:new_surname] = surname if surname
    query_data_a[:new_email] = new_email if new_email

    if id != nil && query_data_a.length > 1
      puts query_data_a.join(',')
      dropbox_query(query: '2/team/members/set_profile', query_data: query_data_a, trace: trace)
    end
  end

  def team_info(trace: false)
    # Dropbox rejects this particular POST unless content_type is ''
    # Other posts with no query data seem to work fine with '{}' passed for the query data.
    dropbox_query(query: '2/team/get_info', query_data: '', content_type: '', trace: trace)
  end
end
