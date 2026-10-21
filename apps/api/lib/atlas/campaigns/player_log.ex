defmodule Atlas.Campaigns.PlayerLog do
  @moduledoc """
  One player's recollection of a session. A player has at most one per session.

  Every member of the campaign reads every player log, the GM included. Only its author writes it.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Campaigns,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  alias Atlas.Campaigns.PlayerLog.ActorIsSessionPlayer

  postgres do
    table "player_logs"
    repo Atlas.Repo
  end

  typescript do
    type_name "PlayerLog"
  end

  rich_text do
    section(:body)
  end

  actions do
    defaults [:read]

    read :list do
      argument :session_id, :uuid, allow_nil?: false
      filter expr(session_id == ^arg(:session_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    # Starting a log twice keeps the first one.
    create :create do
      primary? true
      accept [:session_id]
      upsert? true
      upsert_identity :unique_author
      upsert_fields []
      change relate_actor(:author)
    end
  end

  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       session.campaign,
                       gm_id == ^actor(:id) or exists(characters, user_id == ^actor(:id))
                     )
                   )
    end

    policy action_type(:create) do
      authorize_if ActorIsSessionPlayer
    end

    policy action(:save_body) do
      authorize_if expr(author_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Atlas.Campaigns.Session do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :author, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end

  calculations do
    calculate :is_mine, :boolean, expr(author_id == ^actor(:id)), public?: true
    calculate :author_name, :string, expr(author.display_name), public?: true
  end

  identities do
    identity :unique_author, [:session_id, :author_id]
  end
end
