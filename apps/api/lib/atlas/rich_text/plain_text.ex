defmodule Atlas.RichText.PlainText do
  @moduledoc """
  Reads a validated BlockNote document as plain text, for a language model.
  Styles and links are dropped: it is not safe to write this text back. A mention reads as
  `[@Name](atlas-entry:kind:id)`. Headings, lists, quotes and nesting are kept.

  Options:

    * `:labels` - the names of the mentioned entries, from `Atlas.RichText.Mentions.labels/3`.
      An entry that has no name there reads as "Restricted entry". Without this option the name
      is the kind of the entry.
    * `:links` - set to `false` to write `@Name` only, for text that a model reads and never
      writes back.
    * `:at` - set to `false` (with `links: false`) to write `Name` without the `@`.
    * `:images` - set to `true` to write an image as `[image: name - caption]`. Without it an
      image has no text.
  """

  @spec render([map()] | nil, keyword()) :: String.t()
  def render(blocks, opts \\ [])
  def render(nil, _opts), do: ""
  def render(blocks, opts), do: blocks |> lines("", opts) |> Enum.join("\n") |> String.trim()

  defp lines(blocks, indent, opts), do: Enum.flat_map(blocks, &block(&1, indent, opts))

  defp block(%{"type" => "divider"}, _, _), do: []

  defp block(%{"type" => type} = block, indent, opts) do
    text = text(block, opts)
    children = lines(block["children"] || [], indent <> "  ", opts)
    own = if text == "", do: [], else: [indent <> prefix(type, block["props"] || %{}) <> text]
    own ++ children
  end

  @doc """
  One entry per block, nested blocks included: its ID, type, depth and own text (without the
  text of its nested blocks). Takes the same options as `render/2`.
  """
  @spec flat([map()] | nil, keyword()) :: [
          %{id: String.t(), type: String.t(), depth: non_neg_integer(), text: String.t()}
        ]
  def flat(blocks, opts \\ []), do: flat(blocks || [], 0, opts)

  defp flat(blocks, depth, opts) do
    Enum.flat_map(blocks, fn block ->
      own = %{id: block["id"], type: block["type"], depth: depth, text: text(block, opts)}
      [own | flat(block["children"] || [], depth + 1, opts)]
    end)
  end

  defp text(%{"type" => "image", "props" => props}, opts) do
    if Keyword.get(opts, :images, false), do: image(props), else: ""
  end

  defp text(block, opts), do: inline(block["content"], opts)

  defp image(props) do
    case Enum.reject([props["name"], props["caption"]], &(&1 in [nil, ""])) do
      [] -> "[image]"
      parts -> "[image: " <> Enum.join(parts, " - ") <> "]"
    end
  end

  defp prefix("heading", props), do: String.duplicate("#", props["level"] || 1) <> " "
  defp prefix("quote", _), do: "> "
  defp prefix("bulletListItem", _), do: "- "
  defp prefix("numberedListItem", _), do: "1. "
  defp prefix("checkListItem", _), do: "- "
  defp prefix("toggleListItem", _), do: "- "
  defp prefix(_, _), do: ""

  defp inline(nil, _), do: ""

  defp inline(%{"rows" => rows}, opts) do
    Enum.map_join(rows, "\n", fn row ->
      Enum.map_join(row["cells"], " | ", &inline(&1, opts))
    end)
  end

  defp inline(%{"content" => content}, opts), do: inline(content, opts)
  defp inline(nodes, opts) when is_list(nodes), do: Enum.map_join(nodes, &inline_node(&1, opts))

  defp inline_node(%{"type" => "text", "text" => text}, _), do: text
  defp inline_node(%{"type" => "link", "content" => content}, opts), do: inline(content, opts)

  defp inline_node(%{"type" => "mention"} = mention, opts), do: mention_text(mention, opts)

  defp inline_node(cell, opts), do: inline(cell, opts)

  @doc false
  def mention_text(%{"props" => %{"kind" => kind, "id" => id}}, opts) do
    name =
      case Keyword.fetch(opts, :labels) do
        {:ok, labels} -> Map.get(labels, {kind, id}, "Restricted entry")
        :error -> kind
      end

    cond do
      Keyword.get(opts, :links, true) -> "[@#{name}](atlas-entry:#{kind}:#{id})"
      Keyword.get(opts, :at, true) -> "@#{name}"
      true -> name
    end
  end
end
