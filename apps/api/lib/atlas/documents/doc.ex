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

    # Writes Markdown into one rich-text section as a live edit. Used by the MCP tools.
    action :write_text, :map do
      argument :kind, :atom do
        allow_nil? false
        constraints one_of: [:campaign, :session, :character, :note, :player_log]
      end

      argument :id, :uuid, allow_nil?: false

      argument :section, :atom do
        allow_nil? false
        constraints one_of: [:description, :progress_rewards, :log, :prep, :secret_notes, :body]
      end

      argument :markdown, :string, allow_nil?: false

      argument :mode, :atom do
        allow_nil? false
        default :replace
        constraints one_of: [:replace, :append]
      end

      run Atlas.Mcp.WriteText
    end
  end

  # The write action checks the actor against the parent's own policies through `Collab`.
  policies do
    policy action_type([:read, :create]) do
      forbid_if always()
    end

    policy action(:write_text) do
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
