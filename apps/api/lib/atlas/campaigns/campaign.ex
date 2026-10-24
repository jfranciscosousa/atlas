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

    read :list_as_gm do
      filter expr(gm_id == ^actor(:id))
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :create do
      primary? true
      accept [:name]
      change relate_actor(:gm)
    end

    # Plain text for a language model, as the actor may read it. Used by the MCP tools.
    action :describe, :map do
      argument :id, :uuid, allow_nil?: false
      run {Atlas.Mcp.Describe, fields: [:id, :name], sections: [:description, :progress_rewards]}
    end

    # Finds words in the names and the text of the campaign, as the actor may read them. Used by
    # the MCP tools.
    action :search, :map do
      argument :campaign_id, :uuid, allow_nil?: false
      argument :query, :string, allow_nil?: false

      argument :kinds, {:array, :atom},
        constraints: [items: [one_of: [:campaign, :session, :character, :note, :player_log]]]

      argument :limit, :integer, allow_nil?: false, default: 20, constraints: [min: 1, max: 50]
      run Atlas.Mcp.Search
    end
  end

  # The GM and the players (the accounts with a character) can read a campaign. Only the GM can change it.
  # Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action([:describe, :search]) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(gm_id == ^actor(:id) or exists(characters, user_id == ^actor(:id)))
    end

    policy action_type(:update) do
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

    has_many :characters, Atlas.Campaigns.Character
  end

  calculations do
    calculate :is_gm, :boolean, expr(gm_id == ^actor(:id)), public?: true
    calculate :gm_name, :string, expr(gm.display_name), public?: true
  end
end
