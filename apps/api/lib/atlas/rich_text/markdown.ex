defmodule Atlas.RichText.Markdown do
  @moduledoc """
  Reads Markdown as a BlockNote block array, for text that a language model writes, and writes a
  block array as the same Markdown (`render/2`), so a model can read, change and write it back.

  Supported: headings, paragraphs, bullet, numbered and check lists (nested by two-space
  indentation), quotes, fenced code, dividers, images (`![alt](atlas-image:<id>)` on its own
  line), mentions (`[@Name](atlas-entry:<kind>:<id>)`, kind character, session or note; the label
  is dropped, because the editor shows the current name), and **bold**, *italic*, ~~strike~~,
  `code` and [links](https://example.com).
  Tables and raw HTML are not supported and stay plain text. The result still goes through
  `Atlas.RichText.Document`, which has the final say.

  `render/2` loses what Markdown cannot say: underline, colors, alignment, image width, tables
  (written as rows of cells), and Markdown characters inside text (there is no escaping).
  """

  alias Atlas.RichText.PlainText

  @link_schemes ~w(http https mailto)
  @list ~r/^(\s*)([-*+]|\d+[.)])\s+(?:\[([ xX])\]\s+)?(.*)$/
  @mention ~r/\Aatlas-entry:(character|session|note):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z/
  @image ~r/^!\[([^\]]*)\]\((atlas-image:[0-9a-f-]{36})\)\s*$/
  @inline [
    {:link, ~r/\[([^\]]+)\]\(([^)\s]+)\)/},
    {:code, ~r/`([^`]+)`/},
    {:bold_italic, ~r/\*\*\*(.+?)\*\*\*/},
    {:bold, ~r/\*\*(.+?)\*\*/},
    {:strike, ~r/~~(.+?)~~/},
    {:italic, ~r/\*([^*\s][^*]*?)\*/}
  ]

  @spec parse(String.t()) :: [map()]
  def parse(markdown) when is_binary(markdown) do
    markdown |> String.split(~r/\R/) |> blocks([])
  end

  @list_types ~w(bulletListItem numberedListItem checkListItem toggleListItem)

  @doc """
  Writes a validated block array as Markdown that `parse/1` reads back. Options are the
  `:labels` of `Atlas.RichText.PlainText`.
  """
  @spec render([map()] | nil, keyword()) :: String.t()
  def render(blocks, opts \\ [])
  def render(nil, _opts), do: ""

  def render(blocks, opts) do
    blocks
    |> Enum.zip(render_each(blocks, opts))
    |> Enum.reject(fn {_block, markdown} -> markdown == "" end)
    |> Enum.reduce({nil, []}, fn {%{"type" => type}, markdown}, {previous, acc} ->
      # Items of one list stay together. Anything else needs a blank line to stay a block.
      separator =
        cond do
          acc == [] -> ""
          previous in @list_types and type in @list_types -> "\n"
          true -> "\n\n"
        end

      {type, [acc, separator, markdown]}
    end)
    |> elem(1)
    |> IO.iodata_to_binary()
  end

  @doc "The Markdown of each top-level block, with its children. An empty block gives `\"\"`."
  @spec render_each([map()], keyword()) :: [String.t()]
  def render_each(blocks, opts \\ []),
    do: Enum.map(blocks, &(&1 |> lines("", opts) |> Enum.join("\n")))

  defp lines(block, indent, opts) do
    own =
      case block do
        %{"type" => "divider"} -> ["---"]
        %{"type" => "image", "props" => props} -> ["![#{caption(props)}](#{props["url"]})"]
        %{"type" => "codeBlock"} -> code(block)
        %{"type" => "table", "content" => %{"rows" => rows}} -> Enum.map(rows, &row(&1, opts))
        %{"type" => type} -> text_line(type, block, opts)
      end

    children = Enum.flat_map(block["children"] || [], &lines(&1, indent <> "  ", opts))
    Enum.map(own, &(indent <> &1)) ++ children
  end

  defp caption(props), do: String.replace(props["caption"] || "", ~r/[\[\]\r\n]/, " ")

  defp code(block) do
    language = get_in(block, ["props", "language"]) || ""
    text = for %{"text" => text} <- List.wrap(block["content"]), into: "", do: text
    ["```" <> language] ++ String.split(text, "\n") ++ ["```"]
  end

  defp row(%{"cells" => cells}, opts), do: Enum.map_join(cells, " | ", &inline_text(&1, opts))

  defp text_line(type, block, opts) do
    case inline_text(block["content"], opts) do
      "" -> []
      text -> [prefix(type, block["props"] || %{}) <> text]
    end
  end

  defp prefix("heading", props), do: String.duplicate("#", props["level"] || 1) <> " "
  defp prefix("quote", _), do: "> "
  defp prefix("numberedListItem", _), do: "1. "
  defp prefix("checkListItem", %{"checked" => true}), do: "- [x] "
  defp prefix("checkListItem", _), do: "- [ ] "
  defp prefix(type, _) when type in @list_types, do: "- "
  defp prefix(_, _), do: ""

  defp inline_text(nil, _), do: ""
  defp inline_text(%{"content" => content}, opts), do: inline_text(content, opts)
  defp inline_text(nodes, opts), do: Enum.map_join(nodes, &node_text(&1, opts))

  defp node_text(%{"type" => "mention"} = mention, opts),
    do: PlainText.mention_text(mention, opts)

  defp node_text(%{"type" => "link", "href" => href, "content" => content}, opts),
    do: "[#{inline_text(content, opts)}](#{href})"

  defp node_text(%{"type" => "text", "text" => text, "styles" => styles}, _opts) do
    [_, before, core, trailing] = Regex.run(~r/\A(\s*)(.*?)(\s*)\z/s, text)

    # Whitespace stays outside the marks: `** a**` does not read back as bold.
    if core == "", do: text, else: before <> style(core, styles) <> trailing
  end

  defp node_text(_other, _opts), do: ""

  defp style(text, %{"code" => true}), do: "`#{text}`"

  defp style(text, styles) do
    Enum.reduce([{"strike", "~~"}, {"italic", "*"}, {"bold", "**"}], text, fn {name, mark}, acc ->
      if styles[name], do: mark <> acc <> mark, else: acc
    end)
  end

  defp blocks([], acc), do: Enum.reverse(acc)

  defp blocks(["```" <> language | rest], acc) do
    {code, rest} = Enum.split_while(rest, &(not String.starts_with?(&1, "```")))
    props = if language == "", do: %{}, else: %{"language" => String.trim(language)}
    block = block("codeBlock", props, Enum.reject([text(Enum.join(code, "\n"), %{})], &is_nil/1))
    blocks(Enum.drop(rest, 1), [block | acc])
  end

  defp blocks([line | rest] = lines, acc) do
    cond do
      String.trim(line) == "" ->
        blocks(rest, acc)

      Regex.match?(~r/^\s*([-*_])(\s*\1){2,}\s*$/, line) ->
        blocks(rest, [drop_content(block("divider", %{}, nil)) | acc])

      match = Regex.run(~r/^(\#{1,6})\s+(.*?)\s*\#*\s*$/, line) ->
        [_, hashes, title] = match
        heading = block("heading", %{"level" => String.length(hashes)}, inline(title))
        blocks(rest, [heading | acc])

      match = Regex.run(~r/^>\s?(.*)$/, line) ->
        blocks(rest, [block("quote", %{}, inline(Enum.at(match, 1))) | acc])

      match = Regex.run(@image, String.trim(line)) ->
        [_, alt, url] = match
        image = drop_content(block("image", %{"url" => url, "caption" => alt}, nil))
        blocks(rest, [image | acc])

      Regex.match?(@list, line) ->
        {items, rest} = Enum.split_while(lines, &Regex.match?(@list, &1))
        blocks(rest, Enum.reverse(nest(Enum.map(items, &list_item/1))) ++ acc)

      true ->
        [first | more] = lines
        {continued, rest} = Enum.split_while(more, &paragraph_line?/1)
        text = Enum.map_join([first | continued], " ", &String.trim/1)
        blocks(rest, [block("paragraph", %{}, inline(text)) | acc])
    end
  end

  defp paragraph_line?(line) do
    String.trim(line) != "" and not String.starts_with?(line, "```") and
      not Regex.match?(~r/^(\#{1,6}\s|>|\s*([-*+]|\d+[.)])\s)/, line)
  end

  defp list_item(line) do
    [_, indent, marker, check, text] = Regex.run(@list, line)

    {type, props} =
      cond do
        check != "" -> {"checkListItem", %{"checked" => check != " "}}
        marker =~ ~r/\d/ -> {"numberedListItem", %{}}
        true -> {"bulletListItem", %{}}
      end

    {String.length(indent), block(type, props, inline(text))}
  end

  # An item with a deeper indent than its predecessor becomes that item's child.
  defp nest([]), do: []

  defp nest([{indent, block} | rest]) do
    {deeper, rest} = Enum.split_while(rest, fn {i, _} -> i > indent end)
    [%{block | "children" => nest(deeper)} | nest(rest)]
  end

  defp block(type, props, content) do
    %{
      "id" => Ash.UUID.generate(),
      "type" => type,
      "props" => props,
      "content" => content,
      "children" => []
    }
  end

  defp drop_content(block), do: Map.delete(block, "content")

  defp inline(text), do: scan(text, %{})

  defp scan("", _styles), do: []

  defp scan(text, styles) do
    found =
      for {kind, regex} <- @inline,
          [{start, length} | groups] <- [Regex.run(regex, text, return: :index)],
          do: {start, length, kind, groups}

    if found == [] do
      [text(text, styles)]
    else
      {start, length, kind, groups} = Enum.min_by(found, &elem(&1, 0))
      parts = for {s, l} <- groups, do: binary_part(text, s, l)
      matched = binary_part(text, start, length)
      rest = binary_part(text, start + length, byte_size(text) - start - length)

      Enum.reject(
        [text(binary_part(text, 0, start), styles) | span(kind, matched, parts, styles)],
        &is_nil/1
      ) ++
        scan(rest, styles)
    end
  end

  defp span(:link, matched, [label, url], styles) do
    cond do
      match = Regex.run(@mention, url) ->
        [_, kind, id] = match
        [%{"type" => "mention", "props" => %{"kind" => kind, "id" => id}}]

      URI.parse(url).scheme in @link_schemes ->
        [%{"type" => "link", "href" => url, "content" => scan(label, styles)}]

      true ->
        [text(matched, styles)]
    end
  end

  defp span(:code, _, [code], styles), do: [text(code, Map.put(styles, "code", true))]

  defp span(:bold_italic, _, [inner], styles),
    do: scan(inner, Map.merge(styles, %{"bold" => true, "italic" => true}))

  defp span(:bold, _, [inner], styles), do: scan(inner, Map.put(styles, "bold", true))
  defp span(:strike, _, [inner], styles), do: scan(inner, Map.put(styles, "strike", true))
  defp span(:italic, _, [inner], styles), do: scan(inner, Map.put(styles, "italic", true))

  defp text("", _styles), do: nil
  defp text(text, styles), do: %{"type" => "text", "text" => text, "styles" => styles}
end
