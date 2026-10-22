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
