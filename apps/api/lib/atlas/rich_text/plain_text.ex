defmodule Atlas.RichText.PlainText do
  @moduledoc """
  Reads a validated BlockNote document as Markdown-like text, for a language model.
  Styles and images are dropped. Headings, lists, quotes and nesting are kept.
  """

  @spec render([map()] | nil) :: String.t()
  def render(nil), do: ""
  def render(blocks), do: blocks |> lines("") |> Enum.join("\n") |> String.trim()

  defp lines(blocks, indent), do: Enum.flat_map(blocks, &block(&1, indent))

  defp block(%{"type" => "divider"}, _), do: []

  defp block(%{"type" => type} = block, indent) do
    text = inline(block["content"])
    children = lines(block["children"] || [], indent <> "  ")
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

  defp inline(nil), do: ""
  defp inline(%{"rows" => rows}), do: Enum.map_join(rows, " | ", &inline(&1["cells"]))
  defp inline(%{"content" => content}), do: inline(content)
  defp inline(nodes) when is_list(nodes), do: Enum.map_join(nodes, &inline_node/1)

  defp inline_node(%{"type" => "text", "text" => text}), do: text
  defp inline_node(%{"type" => "link", "content" => content}), do: inline(content)
  defp inline_node(cell), do: inline(cell)
end
