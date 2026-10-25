defmodule Atlas.Content.EntryRelation do
  @moduledoc """
  A relation between two ends: an entry or a character. For example, an NPC is a member of a
  faction, or an item is held by a character. Each end has a kind and an ID, as a mention has.
  `Atlas.Content.RelationSpec` lists the relations and the kinds each end may have.

  Only the GM adds and removes relations. A reader sees a relation only when the reader can read
  both ends: a relation to a hidden or archived entry is invisible to a player. Removing a
  relation deletes the row. It is a link with no text of its own.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  alias Atlas.Content.Checks.ActorIsCampaignGm
  alias Atlas.Content.EntryRelation.CheckEnds
  alias Atlas.Content.RelationSpec

  postgres do
    table "entry_relations"
    repo Atlas.Repo

    custom_indexes do
      index [:campaign_id]
      index [:from_id]
      index [:to_id]
    end

    check_constraints do
      check_constraint :to_id, "entry_relations_not_itself",
        check: "from_id <> to_id",
        message: "cannot be the same as the first end"

      check_constraint :relation, "entry_relations_relation_known",
        check:
          "relation IN ('member_of', 'located_in', 'headquarters_of', 'held_by', 'allied_with', 'enemy_of', 'involves')",
        message: "is not a relation"
    end

    # An end is an entry or a character, so no foreign key points at either table.
    references do
      reference :from_entry, ignore?: true
      reference :from_character, ignore?: true
      reference :to_entry, ignore?: true
      reference :to_character, ignore?: true
    end
  end

  typescript do
    type_name "EntryRelation"
  end

  actions do
    defaults [:read]

    # Every relation of one entry or character, in both directions.
    read :list do
      argument :campaign_id, :uuid, allow_nil?: false
      argument :end_id, :uuid, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 (from_id == ^arg(:end_id) or to_id == ^arg(:end_id))
             )

      prepare build(sort: [relation: :asc, inserted_at: :asc, id: :asc])
    end

    create :create do
      primary? true
      accept [:campaign_id, :from_kind, :from_id, :to_kind, :to_id, :relation, :label]
      validate CheckEnds
    end

    destroy :destroy do
      primary? true
    end
  end

  # The GM reads every relation. A player reads one when both ends are shown to players: an
  # entry that is not hidden or archived, or a character.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))

      authorize_if expr(
                     exists(campaign.characters, user_id == ^actor(:id)) and
                       (from_kind == :character or
                          exists(from_entry, hidden == false and is_nil(archived_at))) and
                       (to_kind == :character or
                          exists(to_entry, hidden == false and is_nil(archived_at)))
                   )
    end

    policy action(:create) do
      authorize_if ActorIsCampaignGm
    end

    policy action(:destroy) do
      authorize_if expr(exists(campaign, gm_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :from_kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: RelationSpec.ends()
    end

    attribute :from_id, :uuid, allow_nil?: false, public?: true

    attribute :to_kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: RelationSpec.ends()
    end

    attribute :to_id, :uuid, allow_nil?: false, public?: true

    attribute :relation, :atom do
      allow_nil? false
      public? true
      constraints one_of: RelationSpec.relations()
    end

    # Free text that refines the relation, for example "staff".
    attribute :label, :string do
      public? true
      constraints max_length: 100, trim?: true, allow_empty?: false
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Atlas.Campaigns.Campaign do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :from_entry, Atlas.Content.Entry do
      source_attribute :from_id
      define_attribute? false
    end

    belongs_to :from_character, Atlas.Campaigns.Character do
      source_attribute :from_id
      define_attribute? false
    end

    belongs_to :to_entry, Atlas.Content.Entry do
      source_attribute :to_id
      define_attribute? false
    end

    belongs_to :to_character, Atlas.Campaigns.Character do
      source_attribute :to_id
      define_attribute? false
    end
  end

  calculations do
    calculate :from_name,
              :string,
              expr(
                if from_kind == :character do
                  from_character.name || "Unnamed character"
                else
                  from_entry.name
                end
              ),
              public?: true

    calculate :to_name,
              :string,
              expr(
                if to_kind == :character do
                  to_character.name || "Unnamed character"
                else
                  to_entry.name
                end
              ),
              public?: true

    # True when players read the end: a character, or an entry that is shown and not archived.
    # A player reads a relation only when both are true.
    calculate :from_shown,
              :boolean,
              expr(
                from_kind == :character or
                  (from_entry.hidden == false and is_nil(from_entry.archived_at))
              ),
              public?: true

    calculate :to_shown,
              :boolean,
              expr(
                to_kind == :character or
                  (to_entry.hidden == false and is_nil(to_entry.archived_at))
              ),
              public?: true
  end

  identities do
    identity :unique_relation, [:from_id, :to_id, :relation],
      message: "These two are already related this way."
  end

  @doc """
  The relations of an entry as plain data, for the MCP tools. `direction` is `outgoing` when the
  entry is the `from` end. `text` reads the relation from the entry: "member of" or "members".
  """
  def describe(record, actor) do
    relations =
      __MODULE__
      |> Ash.Query.for_read(:list, %{campaign_id: record.campaign_id, end_id: record.id},
        actor: actor
      )
      |> Ash.Query.load([:from_name, :to_name])
      |> Ash.read!()
      |> Enum.map(&view(&1, record.id))

    %{relations: relations}
  end

  @doc "One relation as seen from the end `entry_id`."
  def view(relation, entry_id) do
    spec = Enum.find(RelationSpec.describe(), &(&1.relation == Atom.to_string(relation.relation)))
    outgoing? = relation.from_id == entry_id

    {kind, id, name} =
      if outgoing?,
        do: {relation.to_kind, relation.to_id, relation.to_name},
        else: {relation.from_kind, relation.from_id, relation.from_name}

    %{
      id: relation.id,
      relation: relation.relation,
      direction: if(outgoing?, do: :outgoing, else: :incoming),
      text: if(outgoing?, do: spec.label, else: spec.inverse),
      label: relation.label,
      other: %{kind: kind, id: id, name: name}
    }
  end
end
