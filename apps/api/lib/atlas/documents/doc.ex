defmodule Atlas.Documents.Doc do
  @moduledoc """
  The Yjs state of one rich-text section, and the section revision it projects to.

  The parent's `<section>_json` column stays the read model. This row is the collaboration state.
  Only `Atlas.RichText.Collab` reads or writes it, after it has checked the actor against the
  parent's policies. The policy below denies every other caller.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Documents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @kinds Atlas.Kinds.kinds()
  @sections Atlas.Kinds.all_sections()

  postgres do
    table "rich_text_docs"
    repo Atlas.Repo
  end

  actions do
    defaults [:read]

    create :put do
      primary? true
      accept [:kind, :record_id, :section, :state, :revision, :epoch]
      upsert? true
      upsert_identity :doc
      upsert_fields [:state, :revision, :epoch]
    end

    # Edits the blocks of one rich-text section as a live edit. Used by the MCP tools.
    action :edit_blocks, :map do
      argument :kind, :atom, allow_nil?: false, constraints: [one_of: @kinds]
      argument :id, :uuid, allow_nil?: false
      argument :section, :atom, allow_nil?: false, constraints: [one_of: @sections]
      argument :operations, {:array, :map}, allow_nil?: false
      argument :expected_revision, :integer, constraints: [min: 0]
      argument :remove_images, :boolean, allow_nil?: false, default: false
      argument :delete_many, :boolean, allow_nil?: false, default: false

      run Atlas.Mcp.EditBlocks
    end

    # Reads some blocks of one rich-text section, or its outline. Used by the MCP tools.
    action :read_blocks, :map do
      argument :kind, :atom, allow_nil?: false, constraints: [one_of: @kinds]
      argument :id, :uuid, allow_nil?: false
      argument :section, :atom, allow_nil?: false, constraints: [one_of: @sections]
      argument :ids, {:array, :string}
      argument :outline, :boolean, allow_nil?: false, default: false

      run Atlas.Mcp.ReadBlocks
    end

    # Reads many records, as the matching `get_*` tools read them. Used by the MCP tools.
    action :get_many, :map do
      argument :refs, {:array, :map} do
        allow_nil? false

        constraints min_length: 1,
                    max_length: Atlas.Mcp.Batch.max_items(),
                    items: [
                      fields: [
                        kind: [type: :atom, allow_nil?: false, constraints: [one_of: @kinds]],
                        id: [type: :uuid, allow_nil?: false]
                      ]
                    ]
      end

      run Atlas.Mcp.GetMany
    end

    # Reads blocks of many sections. Used by the MCP tools.
    action :read_blocks_many, :map do
      argument :reads, {:array, :map} do
        allow_nil? false

        constraints min_length: 1,
                    max_length: Atlas.Mcp.Batch.max_items(),
                    items: [
                      fields: [
                        kind: [type: :atom, allow_nil?: false, constraints: [one_of: @kinds]],
                        id: [type: :uuid, allow_nil?: false],
                        section: [
                          type: :atom,
                          allow_nil?: false,
                          constraints: [one_of: @sections]
                        ],
                        ids: [type: {:array, :string}],
                        outline: [type: :boolean]
                      ]
                    ]
      end

      run Atlas.Mcp.ReadBlocksMany
    end

    # Edits many sections as one live edit that succeeds or fails as a whole. Used by the MCP tools.
    action :edit_blocks_many, :map do
      argument :edits, {:array, :map} do
        allow_nil? false

        constraints min_length: 1,
                    max_length: Atlas.Mcp.Batch.max_items(),
                    items: [
                      fields: [
                        kind: [type: :atom, allow_nil?: false, constraints: [one_of: @kinds]],
                        id: [type: :uuid, allow_nil?: false],
                        section: [
                          type: :atom,
                          allow_nil?: false,
                          constraints: [one_of: @sections]
                        ],
                        operations: [type: {:array, :map}, allow_nil?: false],
                        expected_revision: [type: :integer, constraints: [min: 0]],
                        remove_images: [type: :boolean],
                        delete_many: [type: :boolean]
                      ]
                    ]
      end

      run Atlas.Mcp.EditBlocksMany
    end
  end

  # The write action checks the actor against the parent's own policies through `Collab`.
  policies do
    policy action_type([:read, :create]) do
      forbid_if always()
    end

    # Each section is checked against its own parent's policies, as the actor.
    policy action([
             :edit_blocks,
             :read_blocks,
             :get_many,
             :read_blocks_many,
             :edit_blocks_many
           ]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :string, allow_nil?: false, public?: true
    attribute :record_id, :uuid, allow_nil?: false, public?: true
    attribute :section, :string, allow_nil?: false, public?: true
    attribute :state, :binary, allow_nil?: false, public?: true
    attribute :revision, :integer, allow_nil?: false, public?: true

    # Counts how often the state was rebuilt from the JSON. A client that holds an older
    # epoch has a document the server no longer knows, and must start over.
    attribute :epoch, :integer, allow_nil?: false, default: 1, public?: true

    update_timestamp :updated_at
  end

  identities do
    identity :doc, [:kind, :record_id, :section]
  end
end
