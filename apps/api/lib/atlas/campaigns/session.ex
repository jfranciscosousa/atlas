defmodule Atlas.Campaigns.Session do
  @moduledoc """
  One played or planned session of a campaign.

  Every member reads the number, title, played date and log. Only the GM creates a session,
  edits it, and reads or writes its prep. The GM writes live notes in the prep and the final
  record in the log; nothing moves from one to the other by itself.
  Sessions are never archived or deleted. Text only: images belong to campaign sections.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Campaigns,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  alias Atlas.Content.Checks.ActorIsCampaignGm

  postgres do
    table "sessions"
    repo Atlas.Repo
  end

  # A player never receives the prep, even when a request asks for it.
  field_policies do
    field_policy [:prep_json, :prep_schema_version, :prep_revision] do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  typescript do
    type_name "Session"
  end

  rich_text do
    section(:log)
    section(:prep)
  end

  actions do
    defaults [:read]

    read :list do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [number: :desc])
    end

    create :create do
      primary? true
      transaction? true
      accept [:campaign_id]
      change Atlas.Campaigns.Session.AssignNumber
    end

    update :update_details do
      accept [:title, :played_on]
    end
  end

  # Members read a session; the GM changes it. Everyone else gets not found.
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

    policy action_type(:create) do
      authorize_if ActorIsCampaignGm
    end

    policy action_type(:update) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer do
      allow_nil? false
      writable? false
      public? true
    end

    attribute :title, :string do
      public? true
      constraints max_length: 200, trim?: true
    end

    attribute :played_on, :date, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Atlas.Campaigns.Campaign do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_number, [:campaign_id, :number]
  end
end
