defmodule Atlas.Content.Entry do
  @moduledoc """
  A named thing of the game world: an NPC, a location, a faction, an item, a creature or a plot.

  One resource holds every kind. The kind is a label for grouping; it adds no fields and no rules.
  An entry is text: the description holds what players read, and the secret notes hold what only
  the GM reads. Details such as a status, an ancestry or an allegiance belong in that text.

  Only the GM creates, edits, archives and restores entries. A new entry is hidden, and only the
  GM reads a hidden entry. The GM shows it to the players with `set_hidden`, and may hide it again.
  A player never sees a hidden entry or an archived one. An entry is archived, never deleted.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  alias Atlas.Content.Checks.ActorIsCampaignGm
  alias Atlas.Content.EntrySpec

  postgres do
    table "entries"
    repo Atlas.Repo

    custom_indexes do
      index [:campaign_id, :kind, :name]
    end

    check_constraints do
      check_constraint :kind, "entries_kind_known",
        check: "kind IN ('npc', 'location', 'faction', 'item', 'creature', 'plot')",
        message: "is not a kind of entry"
    end
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
    type_name "Entry"
  end

  rich_text do
    section(:description)
    section(:secret_notes)
  end

  actions do
    defaults [:read]

    read :list do
      argument :campaign_id, :uuid, allow_nil?: false
      argument :kind, :atom, constraints: [one_of: EntrySpec.kinds()]
      argument :archived, :boolean, default: false, allow_nil?: false

      # The GM lists only what a player reads, for Preview as player. A player's list is the
      # same with or without it.
      argument :as_player, :boolean, default: false, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 (is_nil(^arg(:kind)) or kind == ^arg(:kind)) and
                 not is_nil(archived_at) == ^arg(:archived) and
                 (not (^arg(:as_player)) or (hidden == false and is_nil(archived_at)))
             )

      prepare build(sort: [name: :asc, id: :asc])
    end

    create :create do
      primary? true
      accept [:campaign_id, :kind, :name]
    end

    update :rename do
      accept [:name]
    end

    # The GM shows an entry to the players, or hides it again.
    update :set_hidden do
      accept [:hidden]
    end

    # Entries are archived, never deleted. An archived entry keeps its ID, and the GM reads it.
    update :archive do
      require_atomic? false
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :restore do
      change set_attribute(:archived_at, nil)
    end

    # Plain text for a language model, as the actor may read it. Used by the MCP tools.
    action :describe, :map do
      argument :id, :uuid, allow_nil?: false

      run {Atlas.Mcp.Describe,
           fields: [:id, :kind, :name, :hidden, :archived_at],
           sections: [:description, :secret_notes]}
    end
  end

  # The GM reads and writes every entry. A player reads an entry only when it is shown and not
  # archived. Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))

      authorize_if expr(
                     hidden == false and is_nil(archived_at) and
                       exists(campaign.characters, user_id == ^actor(:id))
                   )
    end

    policy action(:describe) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if ActorIsCampaignGm
    end

    policy action_type(:update) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      writable? true
      public? true
      constraints one_of: EntrySpec.kinds()
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200, trim?: true
    end

    # A new entry is hidden. Only the GM reads it until the GM shows it.
    attribute :hidden, :boolean do
      allow_nil? false
      default true
      public? true
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

  calculations do
    calculate :is_gm, :boolean, expr(exists(campaign, gm_id == ^actor(:id))), public?: true

    # True when players read this entry. A player gets true for every entry that is readable.
    calculate :shown, :boolean, expr(hidden == false and is_nil(archived_at)), public?: true
  end
end
