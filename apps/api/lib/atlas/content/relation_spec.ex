defmodule Atlas.Content.RelationSpec do
  @moduledoc """
  The fixed list of relations between entries, and the kinds that each end may have.

  An end is an entry or a character. `label` reads from the `from` end to the `to` end, for example
  "member of". `inverse` reads the other way, for example "members". A symmetric relation reads the
  same both ways. This module holds data only, so any module may read it at compile time.
  """

  @entry_kinds Atlas.Content.EntrySpec.kinds()
  @ends [:character | @entry_kinds]
  @people [:npc, :character, :faction, :creature]

  @specs [
    %{
      relation: :member_of,
      label: "member of",
      inverse: "members",
      from: [:npc, :character, :faction],
      to: [:faction]
    },
    %{
      relation: :located_in,
      label: "located in",
      inverse: "contains",
      from: [:npc, :character, :location, :faction, :item, :creature],
      to: [:location]
    },
    %{
      relation: :headquarters_of,
      label: "headquarters of",
      inverse: "headquarters",
      from: [:location],
      to: [:faction]
    },
    %{
      relation: :held_by,
      label: "held by",
      inverse: "holds",
      from: [:item],
      to: [:npc, :character, :faction, :creature]
    },
    %{
      relation: :allied_with,
      label: "allied with",
      inverse: "allied with",
      from: @people,
      to: @people
    },
    %{
      relation: :enemy_of,
      label: "enemy of",
      inverse: "enemy of",
      from: @people,
      to: @people
    },
    %{
      relation: :involves,
      label: "involves",
      inverse: "involved in",
      from: [:plot],
      to: @ends
    }
  ]

  @by_relation Map.new(@specs, &{&1.relation, &1})

  @doc "The kinds that an end may have: `:character` and the entry kinds."
  @spec ends() :: [atom()]
  def ends, do: @ends

  @doc "The relations, in display order."
  @spec relations() :: [atom()]
  def relations, do: Enum.map(@specs, & &1.relation)

  @doc "True when `relation` may join an end of kind `from` to an end of kind `to`."
  @spec allowed?(atom(), atom(), atom()) :: boolean()
  def allowed?(relation, from, to) do
    case Map.fetch(@by_relation, relation) do
      {:ok, spec} -> from in spec.from and to in spec.to
      :error -> false
    end
  end

  @doc "True when the relation reads the same from both ends, such as `:allied_with`."
  @spec symmetric?(atom()) :: boolean()
  def symmetric?(relation) do
    spec = Map.fetch!(@by_relation, relation)
    spec.label == spec.inverse
  end

  @doc "The spec as plain data, for the app."
  @spec describe() :: [map()]
  def describe do
    Enum.map(@specs, fn spec ->
      %{
        relation: Atom.to_string(spec.relation),
        label: spec.label,
        inverse: spec.inverse,
        from: Enum.map(spec.from, &Atom.to_string/1),
        to: Enum.map(spec.to, &Atom.to_string/1)
      }
    end)
  end
end
