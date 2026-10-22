defmodule Atlas.RichText.Markdown do
  @moduledoc """
  Reads Markdown as a BlockNote block array, for text that a language model writes.

  Supported: headings, paragraphs, bullet, numbered and check lists (nested by two-space
  indentation), quotes, fenced code, dividers, images (`![alt](atlas-image:<id>)` on its own
  line), mentions (`[@Name](atlas-entry:<kind>:<id>)`, kind character, session or note; the label
  is dropped, because the editor shows the current name), and **bold**, *italic*, ~~strike~~,
  `code` and [links](https://example.com).
  Tables and raw HTML are not supported and stay plain text. The result still goes through
  `Atlas.RichText.Document`, which has the final say.
  """

  @link_schemes ~w(http https mailto)
  @list ~r/^(\s*)([-*+]|\d+[.)])\s+(?:\[([ xX])\]\s+)?(.*)$/
  @mention ~r/\Aatlas-entry:(character|session|note):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z/
  @image ~r/^!\[([^\]]*)\]\((atlas-image:[0-9a-f-]{36})\)\s*$/
  @inline [
    {:link, ~r/\[([^\]]+)\]\(([^)\s]+)\)/},
    {:code, ~r/`([^`]+)`/},
    {:bold, ~r/\*\*(.+?)\*\*/},
    {:strike, ~r/~~(.+?)~~/},
    {:italic, ~r/\*([^*\s][^*]*?)\*/}
  ]

  @spec parse(String.t()) :: [map()]
  def parse(markdown) when is_binary(markdown) do
    markdown |> String.split(~r/\R/) |> blocks([])
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
  defp span(:bold, _, [inner], styles), do: scan(inner, Map.put(styles, "bold", true))
  defp span(:strike, _, [inner], styles), do: scan(inner, Map.put(styles, "strike", true))
  defp span(:italic, _, [inner], styles), do: scan(inner, Map.put(styles, "italic", true))

  defp text("", _styles), do: nil
  defp text(text, styles), do: %{"type" => "text", "text" => text, "styles" => styles}
end
