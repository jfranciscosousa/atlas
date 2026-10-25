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

    resource Atlas.Content.Entry do
      rpc_action :list_entries, :list
      rpc_action :get_entry, :read, get_by: [:id]
      rpc_action :create_entry, :create
      rpc_action :rename_entry, :rename
      rpc_action :update_entry, :update_details
      rpc_action :set_entry_hidden, :set_hidden
      rpc_action :archive_entry, :archive
      rpc_action :restore_entry, :restore
      rpc_action :get_entry_kinds, :kinds
    end

    resource Atlas.Content.EntryField do
      rpc_action :list_entry_fields, :list
      rpc_action :create_entry_field, :create
      rpc_action :update_entry_field, :update
      rpc_action :move_entry_field, :move
      rpc_action :archive_entry_field, :archive
      rpc_action :restore_entry_field, :restore
    end

    resource Atlas.Content.EntryRelation do
      rpc_action :list_entry_relations, :list
      rpc_action :create_entry_relation, :create
      rpc_action :delete_entry_relation, :destroy
    end
  end

  tools do
    tool :search, Atlas.Search.Request, :search,
      description: """
      Search the names and readable text of the kinds below. Omit campaign_id to search all campaigns you may read, or set it to narrow the search.
      Matching ignores case, accents and punctuation. It accepts one edit for query words of
      4–7 characters and two for longer words. Every query word must match the title together
      with one section. Exact matches rank first. Hidden entries and sections are never searched.
      Mentions use only names you may read; images use their name and caption, not image pixels.
      Each hit includes kind, id, title, campaign_id, campaign_name and matching sections with
      block ids and snippets. A player_log hit also has session_id. Use get_* or read_blocks for more. kinds filters entry types
      (#{Enum.join(Atlas.Kinds.names(), ", ")}). limit defaults to 20, at most 50.
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

    tool :list_entries, Atlas.Content.Entry, :list,
      select: [:id, :kind, :name, :status, :hidden],
      load: [:parent_name],
      description: Atlas.Mcp.Guide.list_entries()

    tool :get_entry, Atlas.Content.Entry, :describe, description: Atlas.Mcp.Guide.get_entry()

    tool :create_entry, Atlas.Content.Entry, :create, description: Atlas.Mcp.Guide.create_entry()

    tool :rename_entry, Atlas.Content.Entry, :rename,
      description: "Rename an entry. Only the GM may."

    tool :update_entry, Atlas.Content.Entry, :update_details,
      description: Atlas.Mcp.Guide.update_entry()

    tool :set_entry_hidden, Atlas.Content.Entry, :set_hidden,
      description:
        "Show an entry to the players (hidden false) or hide it from them (hidden true). Only the GM may. A hidden entry is invisible to players everywhere: lists, search, mentions and relations."

    tool :archive_entry, Atlas.Content.Entry, :archive,
      description: "Archive an entry. Entries are never deleted. Only the GM may."

    tool :restore_entry, Atlas.Content.Entry, :restore,
      description: "Restore an archived entry. Only the GM may."

    tool :list_entry_fields, Atlas.Content.EntryField, :list,
      description: Atlas.Mcp.Guide.list_entry_fields()

    tool :create_entry_field, Atlas.Content.EntryField, :create,
      description: Atlas.Mcp.Guide.create_entry_field()

    tool :update_entry_field, Atlas.Content.EntryField, :update,
      description: Atlas.Mcp.Guide.update_entry_field()

    tool :move_entry_field, Atlas.Content.EntryField, :move,
      description:
        "Move an active custom field to a place in the order of its kind (position 0 is first). The other fields shift. Only the GM may."

    tool :archive_entry_field, Atlas.Content.EntryField, :archive,
      description:
        "Archive a custom field. Fields are never deleted. Its values stay stored and are hidden everywhere until you restore it. Only the GM may."

    tool :restore_entry_field, Atlas.Content.EntryField, :restore,
      description:
        "Restore an archived custom field. It goes last in its kind and its stored values show again. Only the GM may."

    tool :add_entry_relation, Atlas.Content.EntryRelation, :create,
      description: Atlas.Mcp.Guide.add_entry_relation()

    tool :remove_entry_relation, Atlas.Content.EntryRelation, :destroy,
      description:
        "Remove one relation between two entries, by the id that get_entry gives. Only the GM may. It removes the link only; both entries stay."
  end

  resources do
    resource Atlas.Search.Request
    resource Atlas.Content.Note
    resource Atlas.Content.Entry
    resource Atlas.Content.EntryField
    resource Atlas.Content.EntryRelation
  end
end
