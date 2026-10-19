defmodule Atlas.Campaigns.CampaignPlayer do
  @moduledoc """
  A player's membership in a campaign. The GM is not a player: the campaign names them.

  A person joins with the token of an active invitation. The token is the credential, so the
  join action needs only a signed-in account. Leaving and removal do not exist yet.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Campaigns,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  postgres do
    table "campaign_players"
    repo Atlas.Repo
  end

  typescript do
    type_name "CampaignPlayer"
  end

  actions do
    defaults [:read]

    read :list do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    # Joining twice keeps the first membership.
    create :join do
      primary? true
      argument :token, :string, allow_nil?: false
      upsert? true
      upsert_identity :unique_player
      upsert_fields []
      change relate_actor(:user)
      change Atlas.Campaigns.CampaignPlayer.Join
    end
  end

  # Members and the GM can see who plays. Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       campaign,
                       gm_id == ^actor(:id) or exists(players, user_id == ^actor(:id))
                     )
                   )
    end

    policy action(:join) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Atlas.Campaigns.Campaign do
      allow_nil? false
      public? true
    end

    belongs_to :user, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end

  calculations do
    calculate :display_name, :string, expr(user.display_name), public?: true
  end

  identities do
    identity :unique_player, [:campaign_id, :user_id]
  end
end
