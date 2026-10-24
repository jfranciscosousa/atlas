defmodule Atlas.Documents do
  @moduledoc "Server-held state of the documents that people edit together."
  use Ash.Domain, otp_app: :atlas, extensions: [AshAi]

  tools do
    tool :edit_blocks, Atlas.Documents.Doc, :edit_blocks,
      description: Atlas.Mcp.Guide.edit_blocks()

    tool :read_blocks, Atlas.Documents.Doc, :read_blocks,
      description: Atlas.Mcp.Guide.read_blocks()
  end

  resources do
    resource Atlas.Documents.Doc
  end
end
