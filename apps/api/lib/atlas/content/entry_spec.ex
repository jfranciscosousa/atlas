defmodule Atlas.Content.EntrySpec do
  @moduledoc """
  What each kind of world entry has: its label, its statuses and its built-in fields.

  This is the one place that lists them. `Atlas.Content.Entry` validates against it, the app reads
  it through the `entry_kinds` action, and `Atlas.Kinds` takes the kind names from it. A field is
  text and lives in the `fields` map of the entry, so a new field or a new kind needs no column.
  A new kind also needs its name in the check constraint on `entries.kind`.

  Every value is rules-agnostic text or one status from a fixed list. No game-system numbers.
  This module holds data only, so any module may read it at compile time.
  """

  @short 200

  @specs [
    %{
      kind: :npc,
      label: "NPC",
      plural: "NPCs",
      statuses: [:alive, :dead, :missing, :unknown],
      fields: [
        %{key: "ancestry", label: "Ancestry", max_length: @short},
        %{key: "gender", label: "Gender", max_length: @short}
      ]
    },
    %{
      kind: :location,
      label: "Location",
      plural: "Locations",
      statuses: [:active, :destroyed, :abandoned],
      fields: [%{key: "type", label: "Type", max_length: @short}]
    },
    %{
      kind: :faction,
      label: "Faction",
      plural: "Factions",
      statuses: [:active, :disbanded],
      fields: [
        %{key: "type", label: "Type", max_length: @short},
        # Players and the GM read it. The GM writes it.
        %{key: "reputation", label: "Reputation", max_length: 500}
      ]
    },
    %{
      kind: :item,
      label: "Item",
      plural: "Items",
      statuses: [:unknown, :held, :lost, :destroyed],
      fields: [%{key: "type", label: "Type", max_length: @short}]
    },
    %{
      kind: :creature,
      label: "Creature",
      plural: "Creatures",
      statuses: [:active, :defeated],
      fields: [
        %{key: "type", label: "Type", max_length: @short},
        %{key: "source", label: "Source", max_length: @short}
      ]
    },
    %{
      kind: :plot,
      label: "Plot",
      plural: "Plots",
      statuses: [:planned, :active, :done],
      fields: []
    }
  ]

  @by_kind Map.new(@specs, &{&1.kind, &1})

  @doc "The kinds of entry, in display order."
  @spec kinds() :: [atom()]
  def kinds, do: Enum.map(@specs, & &1.kind)

  @doc "Every status of any kind."
  @spec all_statuses() :: [atom()]
  def all_statuses, do: @specs |> Enum.flat_map(& &1.statuses) |> Enum.uniq()

  @doc "The spec of one kind."
  @spec fetch!(atom()) :: map()
  def fetch!(kind), do: Map.fetch!(@by_kind, kind)

  @doc "The statuses of a kind. The first is the default."
  @spec statuses(atom()) :: [atom()]
  def statuses(kind), do: fetch!(kind).statuses

  @doc "The status a new entry of the kind starts with."
  @spec default_status(atom()) :: atom()
  def default_status(kind), do: kind |> statuses() |> hd()

  @doc "The built-in fields of a kind."
  @spec fields(atom()) :: [map()]
  def fields(kind), do: fetch!(kind).fields

  @doc """
  Checks the fields of an entry and returns them without blanks. Values are trimmed. A field that
  the kind does not have, or a value that is not text, is an error.
  """
  @spec normalize_fields(atom(), map() | nil) :: {:ok, map()} | {:error, String.t()}
  def normalize_fields(_kind, nil), do: {:ok, %{}}

  def normalize_fields(kind, fields) when is_map(fields) do
    specs = Map.new(fields(kind), &{&1.key, &1})

    Enum.reduce_while(fields, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      key = to_string(key)

      with {:ok, spec} <-
             Map.fetch(specs, key) |> or_error("#{kind_label(kind)} has no field #{key}"),
           {:ok, text} <- text(value, spec) do
        {:cont, {:ok, if(text == "", do: acc, else: Map.put(acc, key, text))}}
      else
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  def normalize_fields(_kind, _other), do: {:error, "must be a map of field names to text"}

  defp text(value, spec) when is_binary(value) do
    text = String.trim(value)

    if String.length(text) <= spec.max_length,
      do: {:ok, text},
      else: {:error, "#{spec.label} is longer than #{spec.max_length} characters"}
  end

  defp text(nil, _spec), do: {:ok, ""}
  defp text(_value, spec), do: {:error, "#{spec.label} must be text"}

  defp or_error({:ok, _} = ok, _message), do: ok
  defp or_error(:error, message), do: {:error, message}

  defp kind_label(kind), do: fetch!(kind).label

  @doc "The spec as plain data, for the app and the MCP tools."
  @spec describe() :: [map()]
  def describe do
    Enum.map(@specs, fn spec ->
      %{
        kind: Atom.to_string(spec.kind),
        label: spec.label,
        plural: spec.plural,
        statuses: Enum.map(spec.statuses, &Atom.to_string/1),
        default_status: Atom.to_string(hd(spec.statuses)),
        fields: Enum.map(spec.fields, &Map.take(&1, [:key, :label, :max_length]))
      }
    end)
  end
end
