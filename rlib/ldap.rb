require 'net/ldap'
require 'ostruct'

# Encapsulate UoA LDAP (AD) calls
class UOA_LDAP
  LDAP_SERVER = 'uoaadsp01.uoa.auckland.ac.nz'
  # LDAP_SERVER = "ldap.uoa.auckland.ac.nz"  #Disable for the moment, as getting dead LDAP server from VIP address

  # @param conf [Object] must respond to ldap_user and ldap_auth_token
  def initialize(conf:)
    @ldap = Net::LDAP.new host: LDAP_SERVER, # your LDAP host name or IP goes here,
                          port: '389', # your LDAP host port goes here,
                          # :encryption => :simple_tls,
                          base: 'DC=UoA,DC=auckland,DC=ac,DC=nz', # the base of your AD tree goes here,
                          auth: {
                            method: :simple,
                            username: conf.ldap_user, # a user w/sufficient privileges to read from AD goes here,
                            password: conf.ldap_auth_token # the user's password goes here
                          }
  end

  # Get a specific LDAP users (specified by upi:) attributes, as specified by the attributes: Hash.
  # @param upi (String) Users University of Auckland Login name
  # @param attributes (Hash) Keys are the LDAP attribute name and the corresponding values are the attribute names we want to use.
  # @return response (OpenStruct) attribute names, as specified by the values in the attributes Hash argument
  def get_ldap_user_attributies(upi:, attributes:)
    response = OpenStruct.new
    @treebase = 'dc=UoA,dc=auckland,dc=ac,dc=nz'
    filter = Net::LDAP::Filter.eq( 'objectCategory', 'user' ) & Net::LDAP::Filter.eq('cn', "#{upi}")
    attr_list = []
    attributes.each { |k, _v| attr_list << k }
    @ldap.search( base: @treebase, filter: filter, attributes: attr_list ) do |entry|
      attributes.each do |attribute, value|
        response[value] = entry[attribute][0].to_s.strip
      end
      return response # Only want the first entry
    end
    return nil
  end

  # Get all LDAP users (specified by upi:) attributes, as specified by the attributes: Hash.
  # @param upi (String) Users University of Auckland Login name
  # @param attributes (Hash) Keys are the LDAP attribute name and the corresponding values are the attribute names we want to use.
  # @yield response (OpenStruct) attribute names, as specified by the values in the attributes Hash argument
  def get_ldap_allusers_attributies(upi:, attributes:)
    response = OpenStruct.new
    @treebase = 'dc=UoA,dc=auckland,dc=ac,dc=nz'
    filter = Net::LDAP::Filter.eq( 'objectCategory', 'user' ) & Net::LDAP::Filter.eq('cn', "#{upi}")
    attr_list = []
    attributes.each { |k, _v| attr_list << k }
    @ldap.search( base: @treebase, filter: filter, attributes: attr_list ) do |entry|
      attributes.each do |attribute, value|
        response[value] = entry[attribute][0].to_s.strip
      end
      yield response # Only want the first entry
    end
    return nil
  end

  # Get a specific LDAP users (specified by email) attributes, as specified by the attributes: Hash.
  # @param email (String) Users University of Auckland email address
  # @param attributes (Hash) Keys are the LDAP attribute name and the corresponding values are the attribute names we want to use.
  # @return response (OpenStruct) attribute names, as specified by the values in the attributes Hash argument
  def get_ldap_user_attributies_by_email(email:, attributes:)
    response = OpenStruct.new
    @treebase = 'dc=UoA,dc=auckland,dc=ac,dc=nz'
    filter = Net::LDAP::Filter.eq( 'objectCategory', 'user' ) & Net::LDAP::Filter.eq('mail', "#{email}")
    attr_list = []
    attributes.each { |k, _v| attr_list << k }
    @ldap.search( base: @treebase, filter: filter, attributes: attr_list ) do |entry|
      attributes.each do |attribute, value|
        response[value] = entry[attribute][0].to_s.strip
      end
      return response # Only want the first entry
    end
    return nil
  end

  # Get a specific LDAP users (specified by email alias) attributes, as specified by the attributes: Hash.
  # @param email (String) Users University of Auckland email address
  # @param attributes (Hash) Keys are the LDAP attribute name and the corresponding values are the attribute names we want to use.
  # @return response (OpenStruct) attribute names, as specified by the values in the attributes Hash argument
  def get_ldap_user_attributies_by_email_alias(email:, attributes:)
    response = OpenStruct.new
    @treebase = 'dc=UoA,dc=auckland,dc=ac,dc=nz'
    filter = Net::LDAP::Filter.eq( 'objectCategory', 'user' ) & Net::LDAP::Filter.eq('proxyaddresses', "smtp:#{email}")
    attr_list = []
    attributes.each { |k, _v| attr_list << k }
    @ldap.search( base: @treebase, filter: filter, attributes: attr_list ) do |entry|
      attributes.each do |attribute, value|
        response[value] = entry[attribute][0].to_s.strip
      end
      return response # Only want the first entry
    end
    return nil
  end

  # Get an LDAP groups members
  # @param group (String) Users University of Auckland LDAP group name
  # @yield [String,String] Ldap group name, user-name (upi) pairs
  def get_ldap_group_member(groupname:)
    filter = Net::LDAP::Filter.eq( 'objectCategory', 'group' ) & Net::LDAP::Filter.eq('cn', "#{groupname}")
    @treebase = 'OU=Groups,dc=UoA,dc=auckland,dc=ac,dc=nz'

    @ldap.search( base: @treebase, filter: filter, attributes: [ 'member' ] ) do |entry|
      group = entry.dn.split('=')[1].split(',')[0]
      entry.each do |attribute, values|
        next unless attribute.to_s == 'member'

        values.each do |value|
          member = value.split('=')[1].split(',')[0]
          yield group, member
        end
      end
    end
  end

  # Get group members from UoA LDAP service, for a specific group.
  # Targeted at then adding these to a dropbox group of the same name
  # @param group [String] Exact LDAP name of group
  # @yield [OpenStruct] attributes are the
  # @return Array of group members, each member being a Struct that responds to: surname, given_name, email, external_id.
  def get_ldap_group_members(groupname:)
    begin
      group = []
      get_ldap_group_member(groupname: groupname) do |_g, m|
        if block_given?
          yield get_ldap_user_attributies(upi: m, attributes: { 'sn' => 'surname', 'givenname' => 'given_name', 'mail' => 'email', 'cn' => 'external_id' })
        else
          group << get_ldap_user_attributies(upi: m, attributes: { 'sn' => 'surname', 'givenname' => 'given_name', 'mail' => 'email', 'cn' => 'external_id' })
        end
      end
      return group unless block_given?
    rescue StandardError => e
      warn e
    end
  end

  def memberof?(user:, group:)
    @treebase = 'dc=UoA,dc=auckland,dc=ac,dc=nz'
    ou = group.gsub(/^.+\.(.+)$/, '\1')
    filter = "(&(objectCategory=person)(objectclass=user)(memberOf=CN=#{group},OU=#{ou},OU=Groups,DC=UoA,DC=auckland,DC=ac,DC=nz)(cn=#{user}))"
    @ldap.search( base: @treebase, filter: filter, attributes: [ 'cn' ] ) do |_entry|
      return true
    end
    return false
  end

  def old_memberof?(user:, group:, quiet: false ) # rubocop:disable Lint/UnusedMethodArgument # Want this method to have a standard set of arguments
    filter = Net::LDAP::Filter.eq( 'objectCategory', 'user' ) & Net::LDAP::Filter.eq('cn', "#{user}*")
    @ldap.search( base: @treebase, filter: filter, attributes: [ 'memberOf' ] ) do |entry|
      entry.each do |_attribute, values|
        values.each do |value|
          cn = value.strip.split(',')[0].split('=')[1]
          return true if group == cn
        end
      end
    end
    return false
  end
end
