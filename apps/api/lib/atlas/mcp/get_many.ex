defmodule Atlas.Mcp.GetMany do
  @moduledoc """
  Reads many records in one call. It implements `get_many`: for each `{kind, id}` it describes the
  record with the options of the `describe` action that the matching `get_*` tool runs, so a record
  looks the same through both.

  The records of one resource are read in one query, and the mentions of one campaign are named in
  one lookup. The number of queries grows with the number of resources and campaigns in the call,
  not with the number of records.

  Each read stands alone, as the actor. A record that does not exist, one the actor may not read,
  and one of another kind give the same `error`, so the error never shows that a hidden record
  exists. A failed read does not stop the others.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Kinds
  alias Atlas.Mcp.{Describe, Records}

  @not_found "is not a record that exists and that you may read"

  @impl true
  def run(input, _opts, %{actor: actor}) do
    refs = input.arguments.refs
    described = describe_all(refs, actor)

    results =
      Enum.map(refs, fn %{kind: kind, id: id} = ref ->
        case Map.fetch(described, {kind, id}) do
          {:ok, record} -> Map.put(Map.take(ref, [:kind, :id]), :record, record)
          :error -> Map.put(Map.take(ref, [:kind, :id]), :error, @not_found)
        end
      end)

    {:ok, %{results: results}}
  end

  # %{{kind, id} => described record}, for the refs that the actor may read.
  defp describe_all(refs, actor) do
    refs
    |> Enum.uniq()
    |> Enum.group_by(&Kinds.resource(&1.kind))
    |> Enum.flat_map(fn {resource, refs} -> describe_resource(resource, refs, actor) end)
    |> Map.new()
  end

  defp describe_resource(resource, refs, actor) do
    {Describe, opts} = Ash.Resource.Info.action(resource, :describe).run

    records =
      Records.fetch(resource, Enum.map(refs, & &1.id), actor, Keyword.get(opts, :load, []))

    # World entries share one resource. An entry opens only under its own kind.
    found =
      for %{kind: kind, id: id} <- refs,
          record = Map.get(records, id),
          Kinds.record_kind(resource, record) == kind,
          do: {{kind, id}, record}

    described = Describe.describe(Enum.map(found, &elem(&1, 1)), opts, actor)

    found |> Enum.map(&elem(&1, 0)) |> Enum.zip(described)
  end
end
