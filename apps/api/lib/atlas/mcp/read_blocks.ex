defmodule Atlas.Mcp.ReadBlocks do
  @moduledoc """
  Reads some blocks of one rich-text section as the actor, or an outline of all of them. It
  implements `read_blocks`, for a section that is too long to read whole with `get_*`.

  The normal read policies and field policies apply, as for `get_*`.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Mcp.{BlockView, Describe}
  alias Atlas.RichText
  alias Atlas.RichText.Collab
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Mentions

  @impl true
  def run(input, _opts, %{actor: actor}) do
    args = input.arguments

    with {:ok, target} <- target("#{args.kind}:#{args.id}:#{args.section}"),
         {:ok, record} <- Ash.get(target.resource, target.id, actor: actor),
         true <- Collab.kind_matches?(target, record) || {:error, :forbidden},
         {:ok, blocks, revision} <- section(record, target.section),
         labels = Mentions.labels([blocks], actor, Describe.campaign_id(record)),
         {:ok, result} <- result(blocks, labels, args) do
      {:ok, Map.put(result, :revision, revision)}
    else
      {:error, message} when is_binary(message) -> {:error, error(message)}
      {:error, _} -> {:error, error("is not a section that exists and that you may read")}
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
