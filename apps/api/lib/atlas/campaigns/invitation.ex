defmodule Atlas.Campaigns.Invitation do
  @moduledoc """
  A reusable invite link to a campaign. It has no expiry and works until the GM revokes it.
  Revoking keeps the row and stops future joins; existing characters stay.

  shortcut: one active invitation per campaign (a partial unique index), the token is stored
  in plain text so the GM can copy the link again. Hash it if tokens ever protect more.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Campaigns,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  alias Atlas.Content.Checks.ActorIsCampaignGm

  postgres do
    table "campaign_invitations"
    repo Atlas.Repo

    identity_wheres_to_sql one_active: "revoked_at IS NULL"
  end

  typescript do
    type_name "Invitation"
  end

  actions do
    defaults [:read]

    read :active do
      argument :campaign_id, :uuid, allow_nil?: false
      get? true
      filter expr(campaign_id == ^arg(:campaign_id) and is_nil(revoked_at))
    end

    # The token is the credential. Any signed-in holder can look up an active link.
    read :by_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(token == ^arg(:token) and is_nil(revoked_at))
    end

    create :create do
      primary? true
      accept [:campaign_id]
    end

    update :revoke do
      change set_attribute(:revoked_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action(:by_token) do
      authorize_if always()
    end

    policy action([:read, :active]) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if ActorIsCampaignGm
    end

    policy action_type(:update) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :token, :string do
      allow_nil? false
      writable? false
      public? true
      default fn -> :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false) end
    end

    attribute :revoked_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Atlas.Campaigns.Campaign do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  calculations do
    calculate :campaign_name, :string, expr(campaign.name), public?: true
    calculate :gm_name, :string, expr(campaign.gm.display_name), public?: true
  end

  identities do
    identity :unique_token, [:token]
    identity :one_active, [:campaign_id], where: expr(is_nil(revoked_at))
  end
end
