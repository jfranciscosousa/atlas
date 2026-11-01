defmodule Atlas.RichText.Markdown do
  @moduledoc """
  Reads a validated BlockNote document as Markdown, for a language model that follows the text
  and never writes it back: block IDs, colors and alignment are dropped, and underline has no
  Markdown form. Headings, lists, quotes, code, tables, links, bold, italic, strike and inline
  code are kept. An image reads as `[image: caption]`.

  Writes still go through `edit_blocks`: this text is never a way to edit.
  """

  alias Atlas.RichText.PlainText

  @lists ~w(bulletListItem numberedListItem checkListItem toggleListItem)

  @spec render([map()] | nil) :: String.t()
  def render(nil), do: ""
  def render(blocks), do: blocks |> body("") |> String.trim()

  # Consecutive items of a list stay together. Every other block sits in its own paragraph.
  defp body(blocks, indent) do
    {parts, _number} =
      Enum.map_reduce(blocks, 0, fn block, number ->
        number = if block["type"] == "numberedListItem", do: number + 1, else: 0
        {{block["type"], block(block, indent, number)}, number}
      end)

    parts
    |> Enum.reject(fn {_type, text} -> text == "" end)
    |> Enum.chunk_while(
      [],
      fn
        {type, text}, [] ->
          {:cont, [{type, text}]}

        {type, text}, [{prev, _} | _] = acc when type in @lists and prev in @lists ->
          {:cont, [{type, text} | acc]}

        part, acc ->
          {:cont, Enum.reverse(acc), [part]}
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.map_join("\n\n", fn group -> Enum.map_join(group, "\n", &elem(&1, 1)) end)
  end

  defp block(%{"type" => "divider"}, indent, _), do: indent <> "---"

  defp block(%{"type" => "image", "props" => props}, indent, _) do
    case props["caption"] do
      caption when caption in [nil, ""] -> indent <> "[image]"
      caption -> indent <> "[image: " <> caption <> "]"
    end
  end

  defp block(%{"type" => "codeBlock"} = block, indent, _) do
    language = get_in(block, ["props", "language"]) || ""
    text = PlainText.render([%{block | "children" => []}])
    fenced = indent <> "```" <> language <> "\n" <> text <> "\n" <> indent <> "```"
    fenced <> children(block, indent)
  end

  defp block(%{"type" => "table", "content" => %{"rows" => rows}} = block, indent, _) do
    [header | rest] = Enum.map(rows, fn row -> Enum.map(row["cells"], &cell/1) end)
    columns = length(header)

    lines =
      [header, List.duplicate("---", columns) | rest]
      |> Enum.map(&(indent <> "| " <> Enum.join(&1, " | ") <> " |"))

    Enum.join(lines, "\n") <> children(block, indent)
  end

  defp block(%{"type" => type} = block, indent, number) do
    text = inline(block["content"])

    own =
      if text == "", do: "", else: indent <> prefix(type, block["props"] || %{}, number) <> text

    own <> children(block, indent)
  end

  defp children(%{"children" => [_ | _] = children}, indent) do
    nested = body(children, indent <> "  ")
    if nested == "", do: "", else: "\n" <> nested
  end

  defp children(_, _), do: ""

  defp prefix("heading", props, _), do: String.duplicate("#", props["level"] || 1) <> " "
  defp prefix("quote", _, _), do: "> "
  defp prefix("bulletListItem", _, _), do: "- "
  defp prefix("numberedListItem", _, number), do: "#{number}. "
  defp prefix("checkListItem", %{"checked" => true}, _), do: "- [x] "
  defp prefix("checkListItem", _, _), do: "- [ ] "
  defp prefix("toggleListItem", _, _), do: "- "
  defp prefix(_, _, _), do: ""

  defp cell(nodes),
    do: nodes |> inline() |> String.replace("\n", " ") |> String.replace("|", "\\|")

  defp inline(nil), do: ""
  defp inline(text) when is_binary(text), do: text
  defp inline(%{"content" => content}), do: inline(content)
  defp inline(nodes) when is_list(nodes), do: Enum.map_join(nodes, &inline_node/1)

  defp inline_node(%{"type" => "text", "text" => text} = leaf),
    do: styled(text, leaf["styles"] || %{})

  defp inline_node(%{"type" => "link", "href" => href, "content" => content}),
    do: "[" <> inline(content) <> "](" <> href <> ")"

  defp inline_node(%{"type" => "mention"} = mention),
    do: PlainText.mention_text(mention, links: false)

  defp inline_node(other), do: inline(other)

  defp styled("", _), do: ""

  defp styled(text, styles) do
    Enum.reduce(
      [{"code", "`"}, {"bold", "**"}, {"italic", "*"}, {"strike", "~~"}],
      text,
      fn {style, mark}, acc -> if styles[style] == true, do: mark <> acc <> mark, else: acc end
    )
  end
end
