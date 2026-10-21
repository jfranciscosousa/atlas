defmodule Atlas.Campaigns.Character do
  @moduledoc """
  A character in a campaign. Every account that joins a campaign plays one or more characters.

  The account is the player: the person at the table. `player_name` is that person's name. The
  character's own `name` starts empty and shows as "Unnamed character".

  A person joins with the token of an active invitation. The token is the credential, so the
  join action needs only a signed-in account. Joining creates the first character; joining again
  keeps it. A player adds more characters with `create`. Leaving and removal do not exist yet.

  Every member reads a character and its description. The player and the GM write the
  description. Only the player writes the name. The secret notes belong to the GM alone: no
  other member reads or writes them.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Campaigns,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  postgres do
    table "characters"
    repo Atlas.Repo
  end

  # A player never receives the secret notes, even when a request asks for them.
  field_policies do
    field_policy [:secret_notes_json, :secret_notes_schema_version, :secret_notes_revision] do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  typescript do
    type_name "Character"
  end

  rich_text do
    section(:description)
    section(:secret_notes)
  end

  actions do
    defaults [:read]

    read :list do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    # Joining twice keeps the first character.
    create :join do
      primary? true
      argument :token, :string, allow_nil?: false
      change Atlas.Campaigns.Character.Join
      manual Atlas.Campaigns.Character.JoinManual
    end

    create :create do
      accept [:campaign_id]
      change relate_actor(:user)
    end

    update :rename do
      accept [:name]
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
                       gm_id == ^actor(:id) or exists(characters, user_id == ^actor(:id))
                     )
                   )
    end

    policy action(:join) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if Atlas.Campaigns.Character.ActorIsCampaignPlayer
    end

    policy action(:rename) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action(:save_description) do
      authorize_if expr(user_id == ^actor(:id))
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end

    policy action(:save_secret_notes) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      public? true
      constraints max_length: 200, trim?: true
    end

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
    calculate :player_name, :string, expr(user.display_name), public?: true
    calculate :is_mine, :boolean, expr(user_id == ^actor(:id)), public?: true
  end
end
