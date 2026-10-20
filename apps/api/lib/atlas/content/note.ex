defmodule Atlas.Content.Note do
  @moduledoc """
  A free-form campaign document: a plot, a guide, a handout, anything that fits no other kind.

  Any member creates a note and owns it. A note starts hidden: only its owner and the GM can
  read it. The owner or the GM reveals it, and then every member reads and edits the body.
  Other players never see an archived note.
  Bodies are text only. Images belong to campaign sections, so the body save rejects them.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  alias Atlas.Content.Checks.ActorIsCampaignMember

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
      change relate_actor(:owner)
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

    update :reveal do
      change set_attribute(:revealed, true)
    end

    update :hide do
      change set_attribute(:revealed, false)
    end
  end

  # The GM and the owner see and manage a note. Other members read a revealed, active note and
  # edit its body. Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if ActorIsCampaignMember
    end

    policy action_type(:read) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
      authorize_if expr(owner_id == ^actor(:id))

      authorize_if expr(
                     revealed and is_nil(archived_at) and
                       exists(campaign.players, user_id == ^actor(:id))
                   )
    end

    policy action([:rename, :archive, :restore, :reveal, :hide]) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action(:save_body) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
      authorize_if expr(owner_id == ^actor(:id))

      authorize_if expr(
                     revealed and is_nil(archived_at) and
                       exists(campaign.players, user_id == ^actor(:id))
                   )
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

    attribute :revealed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Atlas.Campaigns.Campaign do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :owner, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end

  calculations do
    calculate :is_owner, :boolean, expr(owner_id == ^actor(:id)), public?: true
    calculate :owner_name, :string, expr(owner.display_name), public?: true
  end
end
