defmodule Atlas.RichText.MarkdownTest do
  use ExUnit.Case, async: true

  alias Atlas.RichText.Markdown

  defp block(type, content, extra \\ %{}) do
    Map.merge(
      %{"id" => "b", "type" => type, "props" => %{}, "content" => content, "children" => []},
      extra
    )
  end

  defp text(text, styles \\ %{}), do: %{"type" => "text", "text" => text, "styles" => styles}

  test "headings, paragraphs and quotes" do
    blocks = [
      block("heading", [text("Recap")], %{"props" => %{"level" => 2}}),
      block("paragraph", [text("Open with the "), text("cliffhanger", %{"bold" => true})]),
      block("quote", [text("Short.")])
    ]

    assert Markdown.render(blocks) == "## Recap\n\nOpen with the **cliffhanger**\n\n> Short."
  end

  test "styles and links" do
    link = %{"type" => "link", "href" => "https://2e.aonprd.com", "content" => [text("AoN")]}

    assert Markdown.render([
             block("paragraph", [
               text("a", %{"italic" => true}),
               text("b", %{"strike" => true}),
               text("c", %{"code" => true}),
               text("d", %{"textColor" => "red", "underline" => true}),
               link
             ])
           ]) == "*a*~~b~~`c`d[AoN](https://2e.aonprd.com)"
  end

  test "lists stay together, numbers count, nesting indents" do
    blocks = [
      block("paragraph", [text("Steps")]),
      block("numberedListItem", [text("One")]),
      block("numberedListItem", [text("Two")], %{
        "children" => [block("bulletListItem", [text("detail")])]
      }),
      block("checkListItem", [text("done")], %{"props" => %{"checked" => true}}),
      block("checkListItem", [text("todo")])
    ]

    assert Markdown.render(blocks) ==
             "Steps\n\n1. One\n2. Two\n  - detail\n- [x] done\n- [ ] todo"
  end

  test "code, tables, images and dividers" do
    blocks = [
      block("codeBlock", [text("a = 1")], %{"props" => %{"language" => "elixir"}}),
      block("table", %{
        "type" => "tableContent",
        "rows" => [
          %{"cells" => [[text("Name")], [text("Level")]]},
          %{"cells" => [[text("Imp")], [text("1")]]}
        ]
      }),
      block("image", nil, %{"props" => %{"url" => "atlas-image:x", "caption" => "Map"}}),
      block("divider", nil)
    ]

    assert Markdown.render(blocks) ==
             "```elixir\na = 1\n```\n\n| Name | Level |\n| --- | --- |\n| Imp | 1 |\n\n[image: Map]\n\n---"
  end

  test "an empty or missing document is empty text" do
    assert Markdown.render(nil) == ""
    assert Markdown.render([]) == ""
    assert Markdown.render([block("paragraph", [])]) == ""
  end
end
