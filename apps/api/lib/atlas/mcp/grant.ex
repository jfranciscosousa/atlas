defmodule Atlas.Mcp.Grant do
  @moduledoc """
  One connection of an MCP client to an account. Consent creates it with a one-time code. The
  code exchange fills in the access and refresh tokens. The row stores only SHA-256 hashes of
  the code and the tokens, so a database leak gives no working credential.

  An account lists its connections and revokes them. Revoking deletes the row, which ends
  the access token and the refresh token at once.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Mcp,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  postgres do
    table "mcp_grants"
    repo Atlas.Repo
  end

  typescript do
    type_name "McpConnection"
  end

  actions do
    defaults [:read]

    # A grant whose code nobody exchanged is not a connection yet.
    read :list do
      filter expr(user_id == ^actor(:id) and not is_nil(access_token_hash))
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    # The OAuth module runs these without an actor. No RPC action reaches them.
    create :create do
      primary? true

      accept [
        :client_id,
        :user_id,
        :code_hash,
        :code_challenge,
        :redirect_uri,
        :code_expires_at
      ]
    end

    update :issue_tokens do
      accept [:code_hash, :access_token_hash, :access_expires_at, :refresh_token_hash]
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end

    update :touch do
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type([:read, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :code_hash, :string
    attribute :code_challenge, :string, allow_nil?: false
    attribute :redirect_uri, :string, allow_nil?: false
    attribute :code_expires_at, :utc_datetime_usec

    attribute :access_token_hash, :string
    attribute :access_expires_at, :utc_datetime_usec
    attribute :refresh_token_hash, :string
    attribute :last_used_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :user, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :client, Atlas.Mcp.Client do
      allow_nil? false
      attribute_writable? true
    end
  end

  calculations do
    calculate :client_name, :string, expr(client.name), public?: true
  end

  identities do
    identity :unique_code, [:code_hash]
    identity :unique_access_token, [:access_token_hash]
    identity :unique_refresh_token, [:refresh_token_hash]
  end
end
