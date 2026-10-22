defmodule Atlas.RichText.PlainText do
  @moduledoc """
  Reads a validated BlockNote document as Markdown-like text, for a language model.
  Styles and images are dropped. A mention stays as `[@Name](atlas-entry:kind:id)`, so a model
  that writes the text back keeps it. Headings, lists, quotes and nesting are kept.

  Options:

    * `:labels` - the names of the mentioned entries, from `Atlas.RichText.Mentions.labels/2`.
      An entry that has no name there reads as "Restricted entry". Without this option the name
      is the kind of the entry.
    * `:links` - set to `false` to write `@Name` only, for text that a model reads and never
      writes back.
  """

  @spec render([map()] | nil, keyword()) :: String.t()
  def render(blocks, opts \\ [])
  def render(nil, _opts), do: ""
  def render(blocks, opts), do: blocks |> lines("", opts) |> Enum.join("\n") |> String.trim()

  defp lines(blocks, indent, opts), do: Enum.flat_map(blocks, &block(&1, indent, opts))

  defp block(%{"type" => "divider"}, _, _), do: []

  defp block(%{"type" => type} = block, indent, opts) do
    text = inline(block["content"], opts)
    children = lines(block["children"] || [], indent <> "  ", opts)
    own = if text == "", do: [], else: [indent <> prefix(type, block["props"] || %{}) <> text]
    own ++ children
  end

  defp prefix("heading", props), do: String.duplicate("#", props["level"] || 1) <> " "
  defp prefix("quote", _), do: "> "
  defp prefix("bulletListItem", _), do: "- "
  defp prefix("numberedListItem", _), do: "1. "
  defp prefix("checkListItem", _), do: "- "
  defp prefix("toggleListItem", _), do: "- "
  defp prefix(_, _), do: ""

  defp inline(nil, _), do: ""
  defp inline(%{"rows" => rows}, opts), do: Enum.map_join(rows, " | ", &inline(&1["cells"], opts))
  defp inline(%{"content" => content}, opts), do: inline(content, opts)
  defp inline(nodes, opts) when is_list(nodes), do: Enum.map_join(nodes, &inline_node(&1, opts))

  defp inline_node(%{"type" => "text", "text" => text}, _), do: text
  defp inline_node(%{"type" => "link", "content" => content}, opts), do: inline(content, opts)

  defp inline_node(%{"type" => "mention", "props" => %{"kind" => kind, "id" => id}}, opts) do
    name =
      case Keyword.fetch(opts, :labels) do
        {:ok, labels} -> Map.get(labels, {kind, id}, "Restricted entry")
        :error -> kind
      end

    if Keyword.get(opts, :links, true),
      do: "[@#{name}](atlas-entry:#{kind}:#{id})",
      else: "@#{name}"
  end

  defp inline_node(cell, opts), do: inline(cell, opts)
end
