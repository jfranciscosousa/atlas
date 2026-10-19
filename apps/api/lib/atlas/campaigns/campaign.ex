defmodule Atlas.Campaigns.Campaign do
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Campaigns,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  postgres do
    table "campaigns"
    repo Atlas.Repo

    custom_indexes do
      index [:gm_id, :inserted_at, :id]
    end
  end

  typescript do
    type_name "Campaign"
  end

  rich_text do
    section(:description)
    section(:progress_rewards)
  end

  actions do
    defaults [:read]

    read :list do
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :create do
      primary? true
      accept [:name]
      change relate_actor(:gm)
    end
  end

  # Only the GM can see or change a campaign. Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type([:read, :update]) do
      authorize_if expr(gm_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200, trim?: true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :gm, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end
end
