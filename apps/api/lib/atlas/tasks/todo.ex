defmodule Atlas.Tasks.Todo do
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  postgres do
    table "todos"
    repo Atlas.Repo

    custom_indexes do
      index [:user_id, :inserted_at, :id]
    end
  end

  typescript do
    type_name "Todo"
  end

  actions do
    defaults [:read, :destroy]

    read :list do
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :create do
      primary? true
      accept [:title]
      change relate_actor(:user)
    end

    update :update do
      primary? true
      accept [:completed]
    end
  end

  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200, trim?: true
    end

    attribute :completed, :boolean do
      allow_nil? false
      public? true
      default false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end
end
