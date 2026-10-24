defmodule Atlas.RichText.MarkdownTest do
  use ExUnit.Case, async: true

  alias Atlas.RichText.{Document, Markdown, PlainText}

  @image "atlas-image:0b8f7d6e-1c2a-4f3b-9d4e-5a6b7c8d9e0f"

  defp types(blocks), do: Enum.map(blocks, & &1["type"])

  test "reads headings, paragraphs, quotes, dividers, code and images" do
    blocks =
      Markdown.parse("""
      # Title

      One line
      and another.

      > A quote

      ---

      ```elixir
      IO.puts("hi")
      ```

      ![A map](#{@image})
      """)

    assert types(blocks) == ["heading", "paragraph", "quote", "divider", "codeBlock", "image"]

    assert [
             %{"props" => %{"level" => 1}},
             %{"content" => [%{"text" => "One line and another."}]} | _
           ] = blocks

    assert %{"props" => %{"url" => @image, "caption" => "A map"}} = List.last(blocks)
    assert {:ok, _} = Document.cast_input(blocks, [])
  end

  test "nests lists by indentation and reads check lists" do
    blocks = Markdown.parse("- one\n  - nested\n- [x] done\n- [ ] todo\n\n1. first\n2. second")

    assert types(blocks) == [
             "bulletListItem",
             "checkListItem",
             "checkListItem",
             "numberedListItem",
             "numberedListItem"
           ]

    assert [
             %{"children" => [%{"type" => "bulletListItem"}]},
             %{"props" => %{"checked" => true}} | _
           ] = blocks

    assert {:ok, _} = Document.cast_input(blocks, [])
  end

  test "reads inline styles and links, and keeps unsafe links as text" do
    [paragraph] =
      Markdown.parse(
        "A **bold** and *italic* and ~~gone~~ and `code` and [site](https://a.example) and [bad](javascript:x)"
      )

    content = paragraph["content"]

    assert Enum.any?(content, &(&1["styles"] == %{"bold" => true} and &1["text"] == "bold"))
    assert Enum.any?(content, &(&1["styles"] == %{"italic" => true}))
    assert Enum.any?(content, &(&1["styles"] == %{"strike" => true}))
    assert Enum.any?(content, &(&1["styles"] == %{"code" => true}))
    assert Enum.any?(content, &(&1["type"] == "link" and &1["href"] == "https://a.example"))
    assert Enum.any?(content, &(&1["type"] == "text" and &1["text"] =~ "javascript:x"))
    assert {:ok, _} = Document.cast_input([paragraph], [])
  end

  test "text that looks odd still gives valid blocks" do
    for text <- ["", "   ", "####### seven", "#hashtag", "-", "**", "[x](", "```", "> ", "* * *"] do
      assert {:ok, _} = Document.cast_input(Markdown.parse(text), [])
    end
  end

  test "plain text comes back out of the blocks" do
    assert "# Title\nHello world" ==
             "# Title\n\nHello **world**" |> Markdown.parse() |> PlainText.render()
  end

  test "reads a mention link and writes it back" do
    id = "0b8f7d6e-1c2a-4f3b-9d4e-5a6b7c8d9e0f"

    [paragraph] =
      Markdown.parse("Met [@Mira](atlas-entry:character:#{id}) at [home](https://a.example)")

    assert [
             %{"text" => "Met "},
             %{"type" => "mention", "props" => %{"kind" => "character", "id" => ^id}},
             %{"text" => " at "},
             %{"type" => "link"}
           ] = paragraph["content"]

    assert {:ok, _} = Document.cast_input([paragraph], [])
    assert PlainText.render([paragraph]) =~ "Met [@character](atlas-entry:character:#{id}) at "
  end

  test "a mention link with an unknown kind or a bad ID stays text" do
    for url <- ["atlas-entry:campaign:0b8f7d6e-1c2a-4f3b-9d4e-5a6b7c8d9e0f", "atlas-entry:note:x"] do
      [paragraph] = Markdown.parse("[x](#{url})")
      assert [%{"type" => "text"}] = paragraph["content"]
      assert {:ok, _} = Document.cast_input([paragraph], [])
    end
  end

  describe "render/2" do
    @markdown """
    # Title

    Some **bold**, *italic*, ~~gone~~ and `code` with [a link](https://a.example) and a
    [@Mira](atlas-entry:character:0b8f7d6e-1c2a-4f3b-9d4e-5a6b7c8d9e0f).

    > A quote

    ![A keep](atlas-image:0b8f7d6e-1c2a-4f3b-9d4e-5a6b7c8d9e0f)

    - one
      - nested
    - [x] done
    1. first

    ```elixir
    IO.puts(1)
    ```

    ---

    The end
    """

    test "writes Markdown that parse/1 reads back to the same blocks" do
      markdown = String.replace(@markdown, "a\n[@Mira]", "a [@Mira]") |> String.trim()
      blocks = Markdown.parse(markdown)

      assert Markdown.render(blocks) =~ "![A keep](atlas-image:"
      assert strip_ids(Markdown.parse(Markdown.render(blocks))) == strip_ids(blocks)
    end

    test "keeps whitespace outside the marks" do
      [paragraph] = Markdown.parse("a **b** c")

      assert Markdown.render([put_in(paragraph, ["content", Access.at(1), "text"], " b ")]) ==
               "a  **b**  c"
    end

    defp strip_ids(blocks) do
      Enum.map(
        blocks,
        &(&1 |> Map.delete("id") |> Map.update!("children", fn c -> strip_ids(c) end))
      )
    end
  end
end
