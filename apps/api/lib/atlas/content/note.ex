defmodule Atlas.Content.Note do
  @moduledoc """
  A free-form campaign document: a plot, a guide, a handout, anything that fits no other kind.

  Any member creates a note and owns it. The visibility says who reads it:

    * `:only_me` - the owner alone. Not even the GM reads a player's note at this level.
    * `:me_and_gm` - the owner and the GM. A new note starts here.
    * `:character` - the owner, the GM, and the player of the linked character. The player edits
      the body.
    * `:everyone` - every member reads and edits the body.

  The owner or the GM changes the visibility and may link a character. The GM never reads a
  player's `:only_me` note. Other members never see an archived note.
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
      accept [:campaign_id, :title, :visibility, :character_id]
      change relate_actor(:owner)
      validate Atlas.Content.Note.CheckCharacter
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

    update :set_visibility do
      require_atomic? false
      accept [:visibility, :character_id]
      validate Atlas.Content.Note.CheckCharacter
    end

    # Plain text for a language model, as the actor may read it. Used by the MCP tools.
    action :describe, :map do
      argument :id, :uuid, allow_nil?: false

      run {Atlas.Mcp.Describe,
           fields: [:id, :title, :visibility, :character_name, :archived_at],
           load: [:character_name],
           sections: [:body]}
    end
  end

  # The owner and the GM see and manage a note, except the GM never reads a player's `:only_me`
  # note. The player of the linked character reads it at `:character`, and every member reads it
  # at `:everyone`; both edit its body. Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if ActorIsCampaignMember
    end

    policy action_type(:read) do
      authorize_if expr(owner_id == ^actor(:id))
      authorize_if expr(visibility != :only_me and exists(campaign, gm_id == ^actor(:id)))

      authorize_if expr(
                     visibility == :character and is_nil(archived_at) and
                       exists(character, user_id == ^actor(:id))
                   )

      authorize_if expr(
                     visibility == :everyone and is_nil(archived_at) and
                       exists(campaign.characters, user_id == ^actor(:id))
                   )
    end

    policy action(:describe) do
      authorize_if always()
    end

    policy action([:rename, :archive, :restore, :set_visibility]) do
      authorize_if expr(owner_id == ^actor(:id))
      authorize_if expr(visibility != :only_me and exists(campaign, gm_id == ^actor(:id)))
    end

    policy action(:save_body) do
      authorize_if expr(owner_id == ^actor(:id))
      authorize_if expr(visibility != :only_me and exists(campaign, gm_id == ^actor(:id)))

      authorize_if expr(
                     visibility == :character and is_nil(archived_at) and
                       exists(character, user_id == ^actor(:id))
                   )

      authorize_if expr(
                     visibility == :everyone and is_nil(archived_at) and
                       exists(campaign.characters, user_id == ^actor(:id))
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

    attribute :visibility, :atom do
      allow_nil? false
      default :me_and_gm
      public? true
      constraints one_of: [:only_me, :me_and_gm, :character, :everyone]
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

    belongs_to :character, Atlas.Campaigns.Character do
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
    calculate :character_name, :string, expr(character.name), public?: true
  end
end
