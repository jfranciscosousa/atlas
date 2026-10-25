defmodule Atlas.Content.EntryField do
  @moduledoc """
  A custom field: a field that the GM defines for one kind of world entry in one campaign. For
  example a faction gets "Dragonmark" (text), or a location gets "Kingdom" (a link to a location).
  The built-in fields of `Atlas.Content.EntrySpec` are the same in every campaign. A custom field
  belongs to one campaign and is never shared with another.

  The type is text, number, boolean, select or entry (a link to an entry of one kind). `options`
  holds the choices of a select (`choices`) or the target kind of an entry link (`target_kind`).
  The type, the target kind, the kind and the campaign never change. The label, the choices, the
  order and `gm_only` do. A GM-only field is invisible to players: they never read its definition
  or its values.

  The values are in `entries.custom_fields`, keyed by the ID of the field, so a rename changes no
  data. A field is archived, never deleted. An archived field hides its values everywhere, and
  restoring it shows them again. Only the GM creates, changes, orders, archives and restores
  fields.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  alias Atlas.Content.Checks.ActorIsCampaignGm
  alias Atlas.Content.EntryField.{ApplyOptions, CheckLabel, Move, SetPosition}
  alias Atlas.Content.EntrySpec

  @types [:text, :number, :boolean, :select, :entry]

  postgres do
    table "entry_field_definitions"
    repo Atlas.Repo

    custom_indexes do
      index [:campaign_id, :kind, :position]
    end

    # A label is unique among the active fields of one kind in one campaign, ignoring case.
    identity_wheres_to_sql unique_label: "archived_at IS NULL"

    check_constraints do
      check_constraint :kind, "entry_field_definitions_kind_known",
        check: "kind IN ('npc', 'location', 'faction', 'item', 'creature', 'plot')",
        message: "is not a kind of entry"

      check_constraint :type, "entry_field_definitions_type_known",
        check: "type IN ('text', 'number', 'boolean', 'select', 'entry')",
        message: "is not a type of field"
    end
  end

  typescript do
    type_name "EntryField"
  end

  @doc "The types of custom field."
  @spec types() :: [atom()]
  def types, do: @types

  @doc "The choices of a select field."
  @spec choices(map()) :: [String.t()]
  def choices(%{type: :select, options: options}), do: Map.get(options, "choices", [])
  def choices(_field), do: []

  @doc "The kind of entry that an entry field points to, as an atom."
  @spec target_kind(map()) :: atom() | nil
  def target_kind(%{type: :entry, options: %{"target_kind" => kind}}),
    do: String.to_existing_atom(kind)

  def target_kind(_field), do: nil

  actions do
    defaults [:read]

    # The fields of one campaign, in order. A player gets the active fields that are not GM-only.
    read :list do
      argument :campaign_id, :uuid, allow_nil?: false
      argument :kind, :atom, constraints: [one_of: EntrySpec.kinds()]
      argument :archived, :boolean, default: false, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 (is_nil(^arg(:kind)) or kind == ^arg(:kind)) and
                 not is_nil(archived_at) == ^arg(:archived)
             )

      prepare build(sort: [position: :asc, inserted_at: :asc, id: :asc])
    end

    create :create do
      primary? true
      accept [:campaign_id, :kind, :label, :type, :gm_only]

      # Give the choices of a select, or the kind of entry that an entry field points to.
      argument :choices, {:array, :string}
      argument :target_kind, :atom, constraints: [one_of: EntrySpec.kinds()]

      change ApplyOptions
      change CheckLabel
      change SetPosition
    end

    # `choices` is the whole new list of a select. `renamed_choices` maps an old choice to its new
    # name, and the stored values follow. A choice that entries use cannot be removed.
    update :update do
      primary? true
      require_atomic? false
      accept [:label, :gm_only]

      argument :choices, {:array, :string}
      argument :renamed_choices, :map

      change ApplyOptions
      change CheckLabel
    end

    # Moves an active field to a place in the order of its kind. 0 is first.
    update :move do
      require_atomic? false
      argument :position, :integer, allow_nil?: false, constraints: [min: 0]
      change Move
    end

    update :archive do
      require_atomic? false
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :restore do
      require_atomic? false
      change set_attribute(:archived_at, nil)
      change CheckLabel
      change SetPosition
    end
  end

  # The GM reads and writes every field. A player reads an active field that is not GM-only.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))

      authorize_if expr(
                     gm_only == false and is_nil(archived_at) and
                       exists(campaign.characters, user_id == ^actor(:id))
                   )
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

    attribute :label, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 60, trim?: true, allow_empty?: false
    end

    attribute :type, :atom do
      allow_nil? false
      writable? true
      public? true
      constraints one_of: @types
    end

    # `choices` for a select, `target_kind` for an entry field. `ApplyOptions` sets it.
    attribute :options, :map do
      allow_nil? false
      default %{}
      public? true
    end

    # Players never read a GM-only field or its values.
    attribute :gm_only, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
      public? true
    end

    # The label in lower case, for the unique index. `CheckLabel` sets it.
    attribute :label_key, :string, allow_nil?: false, public?: false

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

  identities do
    identity :unique_label, [:campaign_id, :kind, :label_key],
      where: expr(is_nil(archived_at)),
      message: "is already used by another field of this kind"
  end
end
