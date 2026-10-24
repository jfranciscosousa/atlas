defmodule Atlas.Content do
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc, AshAi]

  typescript_rpc do
    resource Atlas.Search.Request do
      rpc_action :search, :search
    end

    resource Atlas.Content.Note do
      rpc_action :list_notes, :list
      rpc_action :get_note, :read, get_by: [:id]
      rpc_action :create_note, :create
      rpc_action :rename_note, :rename
      rpc_action :archive_note, :archive
      rpc_action :restore_note, :restore
      rpc_action :set_note_visibility, :set_visibility
    end
  end

  tools do
    tool :search, Atlas.Search.Request, :search,
      description: """
      Search the names and readable text of campaigns, sessions, characters, notes and player
      logs. Omit campaign_id to search all campaigns you may read, or set it to narrow the search.
      Matching ignores case, accents and punctuation. It accepts one edit for query words of
      4–7 characters and two for longer words. Every query word must match the title together
      with one section. Exact matches rank first. Hidden entries and sections are never searched.
      Mentions use only names you may read; images use their name and caption, not image pixels.
      Each hit includes kind, id, title, campaign_id, campaign_name and matching sections with
      block ids and snippets. A player_log hit also has session_id. Use get_* or read_blocks for more. kinds filters entry types
      (campaign, session, character, note, player_log). limit defaults to 20, at most 50.
      more is true when limit cuts the results. Archived notes are excluded.
      """

    tool :create_note, Atlas.Content.Note, :create,
      description:
        "Create an empty note in a campaign. It starts visible to you and the GM. Use edit_blocks for the body."

    tool :rename_note, Atlas.Content.Note, :rename, description: "Change the title of a note."

    tool :archive_note, Atlas.Content.Note, :archive,
      description: "Archive a note. Notes are never deleted."

    tool :restore_note, Atlas.Content.Note, :restore, description: "Restore an archived note."

    tool :set_note_visibility, Atlas.Content.Note, :set_visibility,
      description:
        "Set who reads a note: only_me (the owner alone), me_and_gm (the owner and the GM), character (also the player of the linked character, give character_id), or everyone (every member)."

    tool :list_notes, Atlas.Content.Note, :list,
      select: [:id, :title, :visibility],
      load: [:character_name],
      description:
        "List the active notes of a campaign that you can read, who may read each, and the linked character."

    tool :get_note, Atlas.Content.Note, :describe,
      description:
        "Read a note: its title, state and body as blocks (see edit_blocks), with the revision of the body."
  end

  resources do
    resource Atlas.Search.Request
    resource Atlas.Content.Note
  end
end
