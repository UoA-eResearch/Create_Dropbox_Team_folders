require 'net/ldap'
require 'ostruct'

class UOA_LDAP
  # @param conf [Object] must respond to ldap_user and ldap_auth_token
  def initialize(conf:)
    @ldap = Net::LDAP.new  :host => "uoa.auckland.ac.nz", # your LDAP host name or IP goes here,
                          :port => "389", # your LDAP host port goes here,
                          #:encryption => :simple_tls,
                          :base => "DC=UoA,DC=auckland,DC=ac,DC=nz", # the base of your AD tree goes here,
                          :auth => {
                            :method => :simple,
                            :username => conf.ldap_user, # a user w/sufficient privileges to read from AD goes here,
                            :password => conf.ldap_auth_token # the user's password goes here
                          }
  end
  
  # Get a specific LDAP users (specified by upi:) attributes, as specified by the attributes: Hash.
  # @param upi (String) Users University of Auckland Login name
  # @param attributes (Hash) Keys are the LDAP attribute name and the corresponding values are the attribute names we want to use.
  # @return response (OpenStruct) attribute names, as specified by the values in the attributes Hash argument
  def get_ldap_user_attributies(upi:, attributes:)
    response = OpenStruct.new
    @treebase = "dc=UoA,dc=auckland,dc=ac,dc=nz"
    filter = Net::LDAP::Filter.eq( "objectCategory","user" ) & Net::LDAP::Filter.eq("cn","#{upi}")
    @ldap.search( :base => @treebase, :filter => filter ) do |entry|
      attributes.each do |attribute,value|
        response[value] = entry[attribute][0].to_s.strip
      end
      return response #Only want the first entry
    end
    return nil
  end

  # Get a specific LDAP users (specified by email) attributes, as specified by the attributes: Hash.
  # @param email (String) Users University of Auckland email address 
  # @param attributes (Hash) Keys are the LDAP attribute name and the corresponding values are the attribute names we want to use.
  # @return response (OpenStruct) attribute names, as specified by the values in the attributes Hash argument
  def get_ldap_user_attributies_by_email(email:, attributes:)
    response = OpenStruct.new
    @treebase = "dc=UoA,dc=auckland,dc=ac,dc=nz"
    filter = Net::LDAP::Filter.eq( "objectCategory","user" ) & Net::LDAP::Filter.eq("mail","#{email}")
    @ldap.search( :base => @treebase, :filter => filter ) do |entry|
      attributes.each do |attribute,value|
        response[value] = entry[attribute][0].to_s.strip
      end
      return response #Only want the first entry
    end
    return nil
  end

  # Get an LDAP groups members
  # @param group (String) Users University of Auckland LDAP group name
  # @yield [String,String] Ldap group name, user-name (upi) pairs
  def get_ldap_group_member(groupname:)
    filter = Net::LDAP::Filter.eq( "objectCategory","group" ) & Net::LDAP::Filter.eq("cn","#{groupname}")
    @treebase = "OU=Groups,dc=UoA,dc=auckland,dc=ac,dc=nz"

    @ldap.search( :base => @treebase, :filter => filter ) do |entry|
      group = entry.dn.split('=')[1].split(',')[0]
      entry.each do |attribute, values|
        if attribute.to_s == 'member'
          values.each do |value|
            member = value.split('=')[1].split(',')[0]
            yield group, member
          end
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
      get_ldap_group_member(groupname: groupname) do |g,m|
        if block_given?
          yield get_ldap_user_attributies(upi: m, attributes: {'sn'=>'surname', 'givenname'=>'given_name', 'mail'=>'email', 'cn'=>'external_id'})
        else
          group << get_ldap_user_attributies(upi: m, attributes: {'sn'=>'surname', 'givenname'=>'given_name', 'mail'=>'email', 'cn'=>'external_id'})
        end
      end
      return group if !block_given?

    rescue Exception => e
      puts e
    end
  end
end
