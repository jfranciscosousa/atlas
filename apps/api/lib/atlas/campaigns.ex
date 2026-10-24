defmodule Atlas.Campaigns do
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc, AshAi]

  typescript_rpc do
    resource Atlas.Campaigns.Campaign do
      rpc_action :list_campaigns, :list
      rpc_action :get_campaign, :read, get_by: [:id]
      rpc_action :create_campaign, :create
    end

    resource Atlas.Campaigns.Session do
      rpc_action :list_sessions, :list
      rpc_action :get_session, :read, get_by: [:id]
      rpc_action :create_session, :create
      rpc_action :update_session_details, :update_details
      rpc_action :draft_session_log, :draft_log
    end

    resource Atlas.Campaigns.PlayerLog do
      rpc_action :list_player_logs, :list
      rpc_action :create_player_log, :create
    end

    resource Atlas.Campaigns.Character do
      rpc_action :list_characters, :list
      rpc_action :get_character, :read, get_by: [:id]
      rpc_action :create_character, :create
      rpc_action :rename_character, :rename
      rpc_action :join_campaign, :join
      rpc_action :create_unclaimed_character, :create_unclaimed
      rpc_action :claim_character, :claim
    end

    resource Atlas.Campaigns.Invitation do
      rpc_action :get_active_invitation, :active, not_found_error?: false
      rpc_action :get_invitation_by_token, :by_token, not_found_error?: false
      rpc_action :create_invitation, :create
      rpc_action :revoke_invitation, :revoke
    end
  end

  tools do
    tool :create_campaign, Atlas.Campaigns.Campaign, :create,
      description: "Create a campaign. You become its GM."

    tool :create_session, Atlas.Campaigns.Session, :create,
      description: "Add the next session to a campaign you run as GM."

    tool :update_session, Atlas.Campaigns.Session, :update_details,
      description:
        "Change the title, the played date or the status (in_prep or done) of a session. Use edit_blocks for the log and the prep."

    tool :rename_character, Atlas.Campaigns.Character, :rename,
      description: "Change the name of a character."

    tool :create_unclaimed_character, Atlas.Campaigns.Character, :create_unclaimed,
      load: [:player_name, :claim_path],
      description:
        "Prepare a character for a player who has no account yet, in a campaign you run as GM. Give the player's name as player_label. The result has claim_path: give the player the link (the app address plus claim_path). The player signs up or signs in through it and claims the character. You manage it until then."

    tool :list_player_logs, Atlas.Campaigns.PlayerLog, :list,
      select: [:id],
      load: [:author_name],
      description: "List the player logs of a session and who wrote each one."

    tool :get_player_log, Atlas.Campaigns.PlayerLog, :describe,
      description: "Read one player log: its text as blocks (see edit_blocks), with its revision."

    tool :list_campaigns, Atlas.Campaigns.Campaign, :list_as_gm,
      select: [:id, :name],
      description: "List the campaigns you run as GM."

    tool :get_campaign, Atlas.Campaigns.Campaign, :describe,
      description:
        "Read a campaign: its name, description and progress/rewards as blocks (see edit_blocks), with their revisions."

    tool :search, Atlas.Campaigns.Campaign, :search,
      description: """
      Find words in a campaign: the names and the text of its campaign pages, sessions (log and
      prep), characters (description and secret notes), notes and player logs, as far as you may
      read them. Every word of query must occur, in any order, in the name of an entry together
      with one of its sections. The text is plain: a mention reads as the name you may see, and an
      image as [image: name - caption]. Each hit has the kind and id of the entry, its title and,
      for each matching section, the blocks that hold a word (with their block id and a snippet).
      Use get_* or read_blocks with those ids for more. kinds limits the search (campaign,
      session, character, note, player_log). more is true when limit cut the list.
      """

    tool :list_sessions, Atlas.Campaigns.Session, :list,
      select: [:id, :number, :title, :played_on, :status],
      description: "List the sessions of a campaign, newest first."

    tool :get_session, Atlas.Campaigns.Session, :describe,
      description:
        "Read a session: its details, the log and the GM-only prep as blocks (see edit_blocks), with their revisions."

    tool :list_characters, Atlas.Campaigns.Character, :list,
      select: [:id, :name],
      load: [:player_name, :claimed],
      description:
        "List the characters of a campaign, who plays them, and whether a player has claimed each one."

    tool :get_character, Atlas.Campaigns.Character, :describe,
      description:
        "Read a character: its name, player, description and GM-only secret notes as blocks (see edit_blocks), with their revisions. The GM also gets the path of the claim link of an unclaimed character."
  end

  resources do
    resource Atlas.Campaigns.Campaign
    resource Atlas.Campaigns.Session
    resource Atlas.Campaigns.PlayerLog
    resource Atlas.Campaigns.Character
    resource Atlas.Campaigns.Invitation
  end
end
