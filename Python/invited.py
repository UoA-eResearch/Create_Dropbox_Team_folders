import dropbox
import json
from pathlib import Path

class DropboxTeam:
  def __init__(self, config_file: str):
    with open(config_file, "r", encoding="utf-8") as f:
        config = json.load(f)
    access_token = config["team_info_token"]
    # Initialize the DropboxTeam client with a team-linked access token
    self.dbx_team = dropbox.DropboxTeam(access_token)
    self.get_team_members()

  def get_team_members(self):
    try:
      # Fetch the initial batch of team members
      self.team_members = []
      result = self.dbx_team.team_members_list_v2()
      self.team_members.extend(result.members)
      while result.has_more:
        result = self.dbx_team.team_members_list_continue_v2(result.cursor)
        self.team_members.extend(result.members)
    except ApiError as err:
      print(f"Dropbox API error: {err}")

  def invited_members(self):
    for m in self.team_members:
      if( m.profile.status._tag == 'invited'):
        yield m.profile

  def print_invited_members(self):
    for member in self.team_members:
      profile = member.profile
      if( profile.status._tag == 'invited' ):
        print(f"UPI: {profile.external_id'}")
        print(f"Email: {profile.email}")
        print(f"Name: {profile.name.display_name}")
        print(f"Invited: {profile.invited_on}")

if __name__ == "__main__":
  base_dir = Path(__file__).resolve().parent
  try:
    dropbox_team = DropboxTeam(f"{base_dir}/../conf/auth.json")
  except (FileNotFoundError, KeyError, json.JSONDecodeError) as err:
    print(f"Configuration error: {err}", file=sys.stderr)
    sys.exit(1)

  # dropbox_team.print_invited_members()
  for m in dropbox_team.invited_members():
    print(f"{m.external_id}, {m.invited_on}")
