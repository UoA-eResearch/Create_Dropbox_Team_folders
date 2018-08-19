# Populate Dropbox Groups
Using the dropbox API to create University Dropbox team folders and their associated groups for ACL management. Populating the groups from the University LDAP, every 4 hours. 

Team folders have arbitrary names, while the LDAP groups used for ACLs are named for the research project code (in Research Project Database). 
i.e. ```research_project_code_rw and research_project_code_ro```
Currently, this mapping is done in conf/projects.json file. The intent is to migrate this to using REST calls to the research project database to retrieve projects with a Dropbox resource.

We set the Dropbox user record external_id to the UoA UPI. This makes API calls for users simpler.

### conf/project.json
Example config file
```
  [
    { "research_code": "ressci201800008", "team_folder": "Worms"},
    { "research_code": "resmed201800012", "team_folder": "Birds"},
    ...
    { "research_code": "ressci201800027", "team_folder": "Food"}
  ]
```
## Authentication
The dropbox API has both user and team calls, and the team calls have four levels of authentication. Each requires a token passed in the REST header. The LDAP has user/password authentication.

### conf/auth.json
Example auth token file
```
{
  "admin_id":              "dbmid:AACf_Jx1Bi1-mkztJOByBIbhU0-mZMfW2cB",
  "team_info_token":       "b88d621596b7e61337e832f7841066a9b88d621596b7e61337e832f7841066a9",
  "team_audit_token":      "b88d621596b7e61337e832f7841066a9b88d621596b7e61337e832f7841066a9",
  "team_file_token":       "b88d621596b7e61337e832f7841066a9b88d621596b7e61337e832f7841066a9", 
  "team_management_token": "b88d621596b7e61337e832f7841066a9b88d621596b7e61337e832f7841066a9",
  "user_token":            "b88d621596b7e61337e832f7841066a9b88d621596b7e61337e832f7841066a9",
  "ldap_user":             "someone",
  "ldap_auth_token":       "b88d621596b7e61337e"
}
```
Nb. Admin user authentication changed ~August 2018. Now admin functions that would have used the user_token now use the team_file_token and a new header is added to the post, referencing an admin's team_member_id.
```
  Dropbox-API-Select-Admin: dbmid:AACf_Jx1Bi1-mkztJOByBIbhU0-mZMfW2cB
```

## Dependencies
```
  gem install wikk_configuration wikk_json 
  gem install nokogiri
  gem install net-ldap
```

## Issues

* The LDAP entries of some users can have an email address that will not be recognised by the University IDP, so SSO will not work for these users (Currently, this looks to be just Computer Science users, but there may be others). Users with a non UoA email addresses will get given a student email address upi@aucklanduni.ac.nz, as these work with the IDP, and all staff are allocated these addresses too. Email to these users may end up in a black hole though, as many staff never read email to these addresses.

* Team folder, groups and user records can be manually edited through the Dropbox Admin web page. Doing so may cause conflicts with the automated update of these entities. 
  * The automated group updates will "CORRECT" any manual changes. 
  * New, manually added team users will not necessarily have all their fields set to the same values as the LDAP.

* The Dropbox API has returned "429 Too Many Requests" when the Dropbox end is busy (certainly wasn't us sending a lot of calls). Current code backs off for 1, then 2,3 and 4 seconds, retrying each time. It then gives up and moves to the next API call.

* Adding existing team users to the team is not an issue (gets ignored), but we have seen "duplicate_external_member_id" errors, when a new user is give an external_id which had been used by a now deleted user. Oddly, a two step process of adding the user in with no external_id, then setting the external_id, does work. 

* Adding an existing member of a group to that group is an error, so a check needs to be made first.

* Adding a non-team member to a group is an error too. This is not just people external to UoA, but anyone in UoA who hasn't been added to the team (so we automatically add UoA staff, if they appear in one of the LDAP groups being used as an ACL). 



