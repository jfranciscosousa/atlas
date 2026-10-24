defmodule Atlas.Content do
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc, AshAi]

  typescript_rpc do
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
    tool :create_note, Atlas.Content.Note, :create,
      description:
        "Create an empty note in a campaign. It starts visible to you and the GM. Use write_text for the body."

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
        "Read a note: its title, state and body as Markdown, with the revision of the body."
  end

  resources do
    resource Atlas.Content.Note
  end
end
