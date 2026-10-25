defmodule Atlas.Content.Entry do
  @moduledoc """
  A named thing of the game world: an NPC, a location, a faction, an item, a creature or a plot.
  One resource holds every kind. `Atlas.Content.EntrySpec` lists the statuses and the built-in
  fields of each kind, so a new field needs no column: the fields are text in the `fields` map.

  Only the GM creates, edits, archives and restores entries. A new entry is hidden, and only the
  GM reads a hidden entry. The GM shows it to the players with `set_hidden`, and may hide it again.
  A player never sees a hidden entry or an archived one. The description is open to everyone who
  reads the entry. The secret notes belong to the GM alone.

  A location may sit inside another location of the same campaign, without cycles. An entry is
  archived, never deleted. Its image is an image ID, as in a document: images stand alone.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  alias Atlas.Content.Checks.ActorIsCampaignGm

  alias Atlas.Content.Entry.{
    ApplyCustomValues,
    ApplyKindData,
    CheckParent,
    CustomValuesView,
    FilterByCustomValue,
    VerifyImage
  }

  alias Atlas.Content.{EntrySpec, RelationSpec}

  postgres do
    table "entries"
    repo Atlas.Repo

    custom_indexes do
      index [:campaign_id, :kind, :name]
      index [:parent_id], where: "parent_id IS NOT NULL"
    end

    check_constraints do
      check_constraint :kind, "entries_kind_known",
        check: "kind IN ('npc', 'location', 'faction', 'item', 'creature', 'plot')",
        message: "is not a kind of entry"

      check_constraint :parent_id, "entries_parent_is_a_location",
        check: "parent_id IS NULL OR (kind = 'location' AND parent_id <> id)",
        message: "is only for a location, and not the location itself"
    end

    references do
      reference :parent, on_delete: :restrict
    end
  end

  # A player never receives the secret notes, even when a request asks for them. A player gets the
  # parent only when the parent is shown to players too.
  field_policies do
    field_policy [:secret_notes_json, :secret_notes_schema_version, :secret_notes_revision] do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end

    field_policy [:parent_id, :parent_name, :parent_shown] do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))

      authorize_if expr(
                     is_nil(parent_id) or
                       exists(parent, hidden == false and is_nil(archived_at))
                   )
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

      # Keeps the entries whose custom field has this value. Both are given together.
      argument :custom_field_id, :uuid
      argument :custom_field_value, :string

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 (is_nil(^arg(:kind)) or kind == ^arg(:kind)) and
                 not is_nil(archived_at) == ^arg(:archived) and
                 (not (^arg(:as_player)) or (hidden == false and is_nil(archived_at)))
             )

      prepare build(sort: [name: :asc, id: :asc])
      prepare FilterByCustomValue
    end

    create :create do
      primary? true
      accept [:campaign_id, :kind, :name, :fields, :parent_id, :image_id]

      # Optional: without it the entry starts with the default status of its kind.
      argument :status, :atom, constraints: [one_of: EntrySpec.all_statuses()]

      argument :custom_values, :map

      change ApplyKindData
      change ApplyCustomValues
      change CheckParent
      change VerifyImage
    end

    update :rename do
      accept [:name]
    end

    # `fields` is merged into the stored fields. A blank value clears one field.
    #
    # `custom_values` maps the ID of a custom field to its value; an empty value clears it.
    update :update_details do
      require_atomic? false
      accept [:status, :fields, :parent_id, :image_id]

      argument :custom_values, :map

      change ApplyKindData
      change ApplyCustomValues
      change CheckParent
      change VerifyImage
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

    # The kinds with their statuses and fields, and the relations. The app reads this to draw forms.
    action :kinds, :map do
      run fn _input, _context ->
        {:ok, %{kinds: EntrySpec.describe(), relations: RelationSpec.describe()}}
      end
    end

    # Plain text for a language model, as the actor may read it. Used by the MCP tools.
    action :describe, :map do
      argument :id, :uuid, allow_nil?: false

      run {Atlas.Mcp.Describe,
           fields: [
             :id,
             :kind,
             :name,
             :status,
             :hidden,
             :fields,
             :parent_id,
             :parent_name,
             :image_id,
             :archived_at,
             :custom_values
           ],
           load: [:parent_name, :custom_values],
           sections: [:description, :secret_notes],
           extra: {Atlas.Content.EntryRelation, :describe}}
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

    policy action([:describe, :kinds]) do
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

    # One of the statuses of the kind. `ApplyKindData` checks it.
    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: EntrySpec.all_statuses()
    end

    # A new entry is hidden. Only the GM reads it until the GM shows it.
    attribute :hidden, :boolean do
      allow_nil? false
      default true
      public? true
    end

    # The built-in text fields of the kind. `ApplyKindData` checks them.
    attribute :fields, :map do
      allow_nil? false
      default %{}
      public? true
    end

    # The values of the custom fields, by the ID of the field. Never public: players must not
    # receive the values of a GM-only field. `custom_values` shows what the actor may read.
    attribute :custom_fields, :map do
      allow_nil? false
      default %{}
      public? false
    end

    # A portrait or cover. Images stand alone, so this is an ID and not a relationship.
    attribute :image_id, :uuid, public?: true

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

    belongs_to :parent, __MODULE__ do
      attribute_writable? true
      public? true
    end
  end

  calculations do
    calculate :is_gm, :boolean, expr(exists(campaign, gm_id == ^actor(:id))), public?: true
    calculate :parent_name, :string, expr(parent.name), public?: true

    # The custom fields of the kind and their values, as the actor may read them.
    calculate :custom_values, {:array, :map}, CustomValuesView, public?: true

    # True when players read this entry. A player gets true for every entry that is readable.
    calculate :shown, :boolean, expr(hidden == false and is_nil(archived_at)), public?: true

    # True when there is no parent, or players read the parent.
    calculate :parent_shown,
              :boolean,
              expr(is_nil(parent_id) or (parent.hidden == false and is_nil(parent.archived_at))),
              public?: true
  end
end
