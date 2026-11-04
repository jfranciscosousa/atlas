defmodule Atlas.Mcp.ReadBlocks do
  @moduledoc """
  Reads some blocks of one rich-text section as the actor, or an outline of all of them. It
  implements `read_blocks`, for a section that is too long to read whole with `get_*`.

  The normal read policies and field policies apply, as for `get_*`. The result also names the
  audience of the section (see `Atlas.Audience`).
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Audience
  alias Atlas.Mcp.{BlockView, Records}
  alias Atlas.RichText
  alias Atlas.RichText.Collab
  alias Atlas.RichText.Collab.Blocks

  @impl true
  def run(input, _opts, %{actor: actor}) do
    case read(actor, input.arguments) do
      {:ok, result} -> {:ok, result}
      {:error, message} -> {:error, error(message)}
    end
  end

  @doc """
  Reads one section as the actor. `args` has `kind`, `id` and `section`, and may have `ids` or
  `outline`. The error is a text for the client. A section that does not exist and one the actor
  may not read give the same text.
  """
  @spec read(struct(), map()) :: {:ok, map()} | {:error, String.t()}
  def read(actor, args), do: actor |> read_many([args]) |> hd()

  @doc """
  Reads many sections as the actor, in the order of `reads` (see `read/2`). The records of one
  resource are read in one query and the mentions of one campaign are named in one lookup, so the
  number of queries does not grow with the number of sections.
  """
  @spec read_many(struct(), [map()]) :: [{:ok, map()} | {:error, String.t()}]
  def read_many(actor, reads) do
    targets = Enum.map(reads, &target("#{&1.kind}:#{&1.id}:#{&1.section}"))
    records = fetch_records(targets, actor)

    sections =
      reads
      |> Enum.zip(targets)
      |> Enum.map(fn {args, target} -> section_of(args, target, records) end)

    # The campaigns of all sections are read in one query, and each campaign is named once.
    readable =
      for {:ok, _args, _blocks, _revision, _audience, record} = section <- sections,
          do: {section, record}

    campaign_ids = readable |> Enum.map(&elem(&1, 1)) |> Records.campaign_ids()

    labels =
      readable
      |> Enum.zip(campaign_ids)
      |> Enum.map(fn {{{:ok, _args, blocks, _revision, _audience, _record}, _}, campaign_id} ->
        {campaign_id, [blocks]}
      end)
      |> Records.labels(actor)

    {results, []} =
      Enum.map_reduce(sections, campaign_ids, fn
        {:ok, args, blocks, revision, audience, _record}, [campaign_id | rest] ->
          {render(args, blocks, revision, audience, Map.fetch!(labels, campaign_id)), rest}

        {:error, message}, rest ->
          {{:error, message}, rest}
      end)

    results
  end

  defp fetch_records(targets, actor) do
    for {:ok, target} <- targets, reduce: %{} do
      acc -> Map.update(acc, target.resource, [target.id], &[target.id | &1])
    end
    |> Enum.flat_map(fn {resource, ids} ->
      resource
      |> Records.fetch(ids, actor)
      |> Enum.map(fn {id, record} -> {{resource, id}, record} end)
    end)
    |> Map.new()
  end

  # A section that does not exist and one the actor may not read give the same text.
  defp section_of(args, {:ok, target}, records) do
    with {:ok, record} <- Map.fetch(records, {target.resource, target.id}),
         true <- Collab.kind_matches?(target, record),
         {:ok, blocks, revision} <- section(record, target.section) do
      {:ok, args, blocks, revision, Audience.of_record(record, target.section), record}
    else
      _ -> {:error, "is not a section that exists and that you may read"}
    end
  end

  defp section_of(_args, {:error, message}, _records), do: {:error, message}

  defp render(args, blocks, revision, audience, labels) do
    case result(blocks, labels, args) do
      {:ok, result} -> {:ok, Map.merge(result, %{revision: revision, audience: audience})}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, _} -> {:error, "is not a section that exists and that you may read"}
    end
  end

  defp target(ref) do
    case Collab.parse(ref) do
      {:ok, target} -> {:ok, target}
      :error -> {:error, "has no such section"}
    end
  end

  # A field policy replaces a hidden section with a `%Ash.ForbiddenField{}`.
  defp section(record, section) do
    case {Map.fetch!(record, RichText.json_attribute(section)),
          Map.fetch!(record, RichText.revision_attribute(section))} do
      {blocks, revision} when is_list(blocks) and is_integer(revision) -> {:ok, blocks, revision}
      _ -> {:error, :forbidden}
    end
  end

  defp result(blocks, labels, %{ids: ids}) when is_list(ids) and ids != [] do
    normalized = BlockView.normalize(blocks)

    with {:ok, found} <- ids |> Enum.map(&Blocks.find(normalized, &1)) |> collect() do
      {:ok, %{blocks: BlockView.render(found, labels)}}
    end
  end

  defp result(blocks, labels, %{outline: true}),
    do: {:ok, %{outline: BlockView.outline(blocks, labels)}}

  defp result(blocks, labels, _), do: {:ok, %{blocks: BlockView.render(blocks, labels)}}

  defp collect(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, block} -> block end)}
      error -> error
    end
  end

  defp error(message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: :id, message: message)
end
