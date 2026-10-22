defmodule Atlas.Mcp.Client do
  @moduledoc """
  An MCP client that registered itself (RFC 7591). It is a public client: it has no secret and
  proves a code exchange with PKCE. Its ID is the OAuth `client_id`.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Mcp,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  postgres do
    table "mcp_clients"
    repo Atlas.Repo
  end

  typescript do
    type_name "McpClient"
  end

  actions do
    defaults [:read]

    create :register do
      primary? true
      accept [:name, :redirect_uris]
    end
  end

  # Registration is open by design: clients register before any account signs in. The controller
  # calls it without an actor. The consent page reads the name of a client to show it.
  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      default "MCP client"
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :redirect_uris, {:array, :string} do
      allow_nil? false
      constraints min_length: 1, max_length: 10, items: [max_length: 500]
    end

    create_timestamp :inserted_at
  end
end
