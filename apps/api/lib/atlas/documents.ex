defmodule Atlas.Documents do
  @moduledoc "Server-held state of the documents that people edit together."
  use Ash.Domain, otp_app: :atlas, extensions: [AshAi]

  tools do
    tool :edit_blocks, Atlas.Documents.Doc, :edit_blocks,
      description: Atlas.Mcp.Guide.edit_blocks()

    tool :read_blocks, Atlas.Documents.Doc, :read_blocks,
      description: Atlas.Mcp.Guide.read_blocks()

    tool :get_many, Atlas.Documents.Doc, :get_many, description: Atlas.Mcp.Guide.get_many()

    tool :read_blocks_many, Atlas.Documents.Doc, :read_blocks_many,
      description: Atlas.Mcp.Guide.read_blocks_many()

    tool :edit_blocks_many, Atlas.Documents.Doc, :edit_blocks_many,
      description: Atlas.Mcp.Guide.edit_blocks_many()
  end

  resources do
    resource Atlas.Documents.Doc
  end
end
