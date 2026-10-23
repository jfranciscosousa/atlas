defmodule Atlas.Campaigns.Character do
  @moduledoc """
  A character in a campaign. Every account that joins a campaign plays one or more characters.

  The account is the player: the person at the table. `player_name` is that person's name. The
  character's own `name` starts empty and shows as "Unnamed character".

  The GM may prepare an unclaimed character for a person who has no account yet. It has no
  account, only a `player_label`, and a single-use claim link. The person opens the link, signs
  up or signs in, and claims it. A person who never signs up stays unclaimed, and the GM manages
  the character. An unclaimed character makes nobody a member.

  A person joins with the token of an active invitation. The token is the credential, so the
  join action needs only a signed-in account. Joining creates the first character; joining again
  keeps it. A player adds more characters with `create`. Leaving and removal do not exist yet.

  Every member reads a character and its description. The player and the GM write the
  description and the name. The secret notes belong to the GM alone: no
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

  # A player never receives the secret notes or the claim link, even when a request asks for them.
  field_policies do
    field_policy [
      :secret_notes_json,
      :secret_notes_schema_version,
      :secret_notes_revision,
      :claim_path
    ] do
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

    # The GM prepares a character for a person who plays without an account, or before they sign up.
    create :create_unclaimed do
      accept [:campaign_id, :player_label]
      validate present(:player_label)
      change set_attribute(:claim_token, &Atlas.Campaigns.Character.new_claim_token/0)
    end

    # The claim page reads this without an account. The token is the credential.
    read :by_claim_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(claim_token == ^arg(:token) and is_nil(user_id))
    end

    # The token is the credential, so claiming needs only a signed-in account.
    create :claim do
      argument :token, :string, allow_nil?: false
      change Atlas.Campaigns.Character.Claim
      manual Atlas.Campaigns.Character.ClaimManual
    end

    # Internal: `claim` calls it after it has checked the token.
    update :assign_player do
      require_atomic? false
      argument :user_id, :uuid, allow_nil?: false

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.force_change_attribute(
          :user_id,
          Ash.Changeset.get_argument(changeset, :user_id)
        )
        |> Ash.Changeset.force_change_attribute(:claim_token, nil)
      end
    end

    update :rename do
      accept [:name]
    end

    # Plain text for a language model, as the actor may read it. Used by the MCP tools.
    action :describe, :map do
      argument :id, :uuid, allow_nil?: false

      run {Atlas.Mcp.Describe,
           fields: [:id, :name, :player_name, :claimed, :claim_path],
           load: [:player_name, :claimed, :claim_path],
           sections: [:description, :secret_notes]}
    end
  end

  # Members and the GM can see who plays. Everyone else gets not found.
  policies do
    # A person without an account opens a claim link, so this read needs no actor.
    bypass action(:by_claim_token) do
      authorize_if always()
    end

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

    policy action(:describe) do
      authorize_if always()
    end

    policy action([:join, :claim]) do
      authorize_if always()
    end

    policy action(:create_unclaimed) do
      authorize_if Atlas.Content.Checks.ActorIsCampaignGm
    end

    policy action(:create) do
      authorize_if Atlas.Campaigns.Character.ActorIsCampaignPlayer
    end

    policy action(:rename) do
      authorize_if expr(user_id == ^actor(:id))
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
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

    # Shown as the player's name until someone claims the character.
    attribute :player_label, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    # Set while the character is unclaimed. Claiming clears it, so a link works once.
    attribute :claim_token, :string

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Atlas.Campaigns.Campaign do
      allow_nil? false
      public? true
    end

    belongs_to :user, Atlas.Accounts.User do
      attribute_writable? false
    end
  end

  calculations do
    calculate :player_name, :string, expr(user.display_name || player_label), public?: true
    calculate :claimed, :boolean, expr(not is_nil(user_id)), public?: true

    calculate :is_mine,
              :boolean,
              expr(not is_nil(user_id) and user_id == ^actor(:id)),
              public?: true

    calculate :claim_path,
              :string,
              expr(if is_nil(claim_token), do: nil, else: "/claim/" <> claim_token),
              public?: true

    calculate :campaign_name, :string, expr(campaign.name), public?: true
    calculate :gm_name, :string, expr(campaign.gm.display_name), public?: true
  end

  identities do
    identity :unique_claim_token, [:claim_token]
  end

  def new_claim_token, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
