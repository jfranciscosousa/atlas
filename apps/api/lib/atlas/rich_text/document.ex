defmodule Atlas.RichText.Document do
  @moduledoc """
  Ash type for a BlockNote document: the native block array, validated against an allow-list.

  Images are stored as `atlas-image:<uuid>` references, never as URLs.
  """
  use Ash.Type

  @schema_version 1
  @max_bytes 1_000_000
  @max_depth 8
  @block_types ~w(paragraph heading quote bulletListItem numberedListItem checkListItem
                  toggleListItem codeBlock table image divider)
  @block_keys ~w(id type props content children)
  @styles ~w(bold italic underline strike code textColor backgroundColor)
  @link_schemes ~w(http https mailto)
  @mention_kinds ~w(character session note)
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @image_ref ~r/\Aatlas-image:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z/

  def schema_version, do: @schema_version

  @doc "Block types a document accepts."
  def block_types, do: @block_types

  @doc "Text styles a document accepts."
  def styles, do: @styles

  @doc "Image IDs referenced by a validated document."
  def image_ids(blocks) do
    blocks
    |> Enum.flat_map(fn block ->
      own =
        case block do
          %{"type" => "image", "props" => %{"url" => "atlas-image:" <> id}} -> [id]
          _ -> []
        end

      own ++ image_ids(block["children"] || [])
    end)
    |> Enum.uniq()
  end

  @doc "`{kind, id}` pairs of the mentions in a validated document."
  def mention_refs(nil), do: []

  def mention_refs(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(fn block ->
      own = block["content"] |> inline_nodes() |> Enum.flat_map(&mention_ref/1)
      own ++ mention_refs(block["children"] || [])
    end)
    |> Enum.uniq()
  end

  defp inline_nodes(%{"rows" => rows}),
    do: Enum.flat_map(rows, fn %{"cells" => cells} -> Enum.flat_map(cells, &inline_nodes/1) end)

  defp inline_nodes(%{"content" => content}), do: inline_nodes(content)
  defp inline_nodes(nodes) when is_list(nodes), do: nodes
  defp inline_nodes(_), do: []

  defp mention_ref(%{"type" => "mention", "props" => %{"kind" => kind, "id" => id}}),
    do: [{kind, id}]

  defp mention_ref(_), do: []

  @impl true
  def storage_type(_), do: :map

  @impl true
  def ecto_type, do: Atlas.RichText.EctoDocument

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, _), do: validate(value)

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, _) when is_list(value), do: {:ok, value}
  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(value, _), do: {:ok, value}

  # Errors name the place of the fault, such as `blocks[2].children[0].content[1]: ...`.
  defp validate(blocks) when is_list(blocks) do
    with :ok <- check_size(blocks),
         :ok <- all(blocks, "blocks", &block(&1, 1)) do
      {:ok, blocks}
    else
      {:error, {path, message}} -> {:error, "#{Enum.join(path, ".")}: #{message}"}
      error -> error
    end
  end

  defp validate(_), do: {:error, "must be a list of blocks"}

  defp check_size(blocks) do
    case Jason.encode(blocks) do
      {:ok, json} when byte_size(json) <= @max_bytes -> :ok
      {:ok, _} -> {:error, "document is larger than #{@max_bytes} bytes"}
      {:error, _} -> {:error, "document is not valid JSON"}
    end
  end

  defp all(items, key, fun) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, {path, message}} -> {:halt, {:error, {["#{key}[#{index}]" | path], message}}}
        {:error, message} -> {:halt, {:error, {["#{key}[#{index}]"], message}}}
      end
    end)
  end

  defp block(_, depth) when depth > @max_depth, do: {:error, "blocks are nested too deeply"}

  defp block(%{"id" => id, "type" => type} = block, depth) when is_binary(id) do
    with :ok <- unknown_keys(block, @block_keys, "block"),
         :ok <- type(type),
         :ok <- props(type, block["props"] || %{}),
         :ok <- content(type, block["content"]),
         children when is_list(children) <- block["children"] || [] do
      all(children, "children", &block(&1, depth + 1))
    else
      {:error, _} = error -> error
      _ -> {:error, "block children must be a list"}
    end
  end

  defp block(_, _), do: {:error, "block needs a string id and a type"}

  defp type(type) when type in @block_types, do: :ok

  defp type(type),
    do:
      {:error, "block type #{inspect(type)} is not allowed; use #{Enum.join(@block_types, ", ")}"}

  defp props("image", %{"url" => url} = props) when is_binary(url) do
    if url == "" or Regex.match?(@image_ref, url),
      do: scalars(props),
      else: {:error, "image url must be an atlas-image reference"}
  end

  defp props("image", _), do: {:error, "image block needs an atlas-image url"}
  defp props(_, props), do: scalars(props)

  defp scalars(props) when is_map(props) do
    if Enum.all?(props, fn {k, v} -> is_binary(k) and scalar?(v) end),
      do: :ok,
      else: {:error, "block props must be scalar values"}
  end

  defp scalars(_), do: {:error, "block props must be a map"}

  defp scalar?(v), do: is_nil(v) or is_binary(v) or is_number(v) or is_boolean(v)

  defp content(_, nil), do: :ok

  defp content("table", %{"type" => "tableContent", "rows" => rows}) when is_list(rows) do
    all(rows, "rows", fn
      %{"cells" => cells} when is_list(cells) -> all(cells, "cells", &cell/1)
      _ -> {:error, "table rows need cells"}
    end)
  end

  defp content("table", _), do: {:error, "table content is invalid"}
  defp content(_, content) when is_list(content), do: all(content, "content", &inline/1)
  defp content(_, _), do: {:error, "block content must be a list"}

  defp cell(%{"content" => content}) when is_list(content), do: all(content, "content", &inline/1)
  defp cell(content) when is_list(content), do: all(content, "content", &inline/1)
  defp cell(_), do: {:error, "table cell is invalid"}

  defp inline(%{"type" => "text", "text" => text} = node) when is_binary(text) do
    with :ok <- unknown_keys(node, ~w(type text styles), "text") do
      styles(node["styles"] || %{})
    end
  end

  defp inline(%{"type" => "link", "href" => href, "content" => content} = node)
       when is_binary(href) and is_list(content) do
    with :ok <- unknown_keys(node, ~w(type href content), "link"),
         :ok <- scheme(href) do
      all(content, "content", &inline/1)
    end
  end

  defp inline(%{"type" => "mention", "props" => %{"kind" => kind, "id" => id} = props} = node)
       when map_size(props) == 2 do
    with :ok <- unknown_keys(node, ~w(type props), "mention") do
      if kind in @mention_kinds and is_binary(id) and Regex.match?(@uuid, id),
        do: :ok,
        else: {:error, "mention needs a kind and an entry id"}
    end
  end

  defp inline(_), do: {:error, "inline content is invalid; use text, link or mention nodes"}

  defp styles(styles) when is_map(styles) do
    case Enum.find(styles, fn {k, v} ->
           k not in @styles or not (is_boolean(v) or is_binary(v))
         end) do
      nil ->
        :ok

      {k, _} when k not in @styles ->
        {:error, "text style #{inspect(k)} is not allowed; use #{Enum.join(@styles, ", ")}"}

      {k, _} ->
        {:error,
         "text style #{inspect(k)} needs true, or a color name for textColor and backgroundColor"}
    end
  end

  defp styles(_), do: {:error, "text styles must be a map"}

  defp scheme(href) do
    case URI.parse(href) do
      %URI{scheme: scheme} when scheme in @link_schemes -> :ok
      _ -> {:error, "link must use http, https or mailto"}
    end
  end

  defp unknown_keys(map, allowed, what) do
    case Map.keys(map) -- allowed do
      [] ->
        :ok

      keys ->
        {:error, "#{what} has unknown keys #{inspect(keys)}; use #{Enum.join(allowed, ", ")}"}
    end
  end
end
