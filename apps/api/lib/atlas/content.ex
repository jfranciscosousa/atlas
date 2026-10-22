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
      rpc_action :reveal_note, :reveal
      rpc_action :hide_note, :hide
    end
  end

  tools do
    tool :create_note, Atlas.Content.Note, :create,
      description:
        "Create an empty note in a campaign. It starts hidden. Use write_text for the body."

    tool :rename_note, Atlas.Content.Note, :rename, description: "Change the title of a note."

    tool :archive_note, Atlas.Content.Note, :archive,
      description: "Archive a note. Notes are never deleted."

    tool :restore_note, Atlas.Content.Note, :restore, description: "Restore an archived note."

    tool :reveal_note, Atlas.Content.Note, :reveal,
      description: "Reveal a note: every member of the campaign can then read it."

    tool :hide_note, Atlas.Content.Note, :hide,
      description: "Hide a note again: only its owner and the GM can read it."

    tool :list_notes, Atlas.Content.Note, :list,
      select: [:id, :title, :revealed],
      description: "List the active notes of a campaign that you can read."

    tool :get_note, Atlas.Content.Note, :describe,
      description: "Read a note: its title, state and body as text."
  end

  resources do
    resource Atlas.Content.Note
  end
end
