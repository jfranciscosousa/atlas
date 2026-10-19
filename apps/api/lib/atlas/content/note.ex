defmodule Atlas.Content.Note do
  @moduledoc """
  A free-form campaign document: a plot, a guide, a handout, anything that fits no other kind.

  shortcut: only the campaign GM can access notes, because campaigns have no members yet.
  Add player-private notes, owners, and sharing when membership exists.
  Bodies are text only. Images belong to campaign sections, so the body save rejects them.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  alias Atlas.Content.Checks.ActorIsCampaignGm

  postgres do
    table "notes"
    repo Atlas.Repo

    custom_indexes do
      index [:campaign_id, :updated_at, :id]
    end
  end

  typescript do
    type_name "Note"
  end

  rich_text do
    section(:body)
  end

  actions do
    defaults [:read]

    read :list do
      argument :campaign_id, :uuid, allow_nil?: false
      argument :archived, :boolean, default: false, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and not is_nil(archived_at) == ^arg(:archived)
             )

      prepare build(sort: [updated_at: :desc, id: :desc])
    end

    create :create do
      primary? true
      accept [:campaign_id, :title]
    end

    update :rename do
      accept [:title]
    end

    # Notes are archived, never deleted. An archived note keeps its ID and stays readable by link.
    update :archive do
      require_atomic? false
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :restore do
      change set_attribute(:archived_at, nil)
    end
  end

  # Only the campaign's GM can see or change a note. Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if ActorIsCampaignGm
    end

    policy action_type([:read, :update]) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200, trim?: true
    end

    attribute :archived_at, :utc_datetime_usec, public?: true

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
end
