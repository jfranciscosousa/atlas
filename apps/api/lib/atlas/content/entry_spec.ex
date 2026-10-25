defmodule Atlas.Content.EntrySpec do
  @moduledoc """
  The kinds of world entry and their labels.

  This is the one place that lists them. `Atlas.Content.Entry` validates against it,
  `Atlas.Kinds` takes the kind names from it, and the MCP guide reads the labels from it.

  A kind is a label for a group of entries, not a schema. An entry is free-form text: its details
  belong in the description and the secret notes. A new kind needs no column, only its name here
  and in the check constraint on `entries.kind`.
  """

  @specs [
    %{kind: :npc, label: "NPC", plural: "NPCs"},
    %{kind: :location, label: "Location", plural: "Locations"},
    %{kind: :faction, label: "Faction", plural: "Factions"},
    %{kind: :item, label: "Item", plural: "Items"},
    %{kind: :creature, label: "Creature", plural: "Creatures"},
    %{kind: :plot, label: "Plot", plural: "Plots"}
  ]

  @by_kind Map.new(@specs, &{&1.kind, &1})

  @doc "The kinds of entry, in display order."
  @spec kinds() :: [atom()]
  def kinds, do: Enum.map(@specs, & &1.kind)

  @doc "The spec of one kind."
  @spec fetch!(atom()) :: map()
  def fetch!(kind), do: Map.fetch!(@by_kind, kind)
end
