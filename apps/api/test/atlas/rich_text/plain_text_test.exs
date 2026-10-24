defmodule Atlas.RichText.PlainTextTest do
  use ExUnit.Case, async: true

  alias Atlas.RichText.PlainText

  defp block(type, text, props \\ %{}, children \\ []) do
    %{
      "id" => "b",
      "type" => type,
      "props" => props,
      "content" => [%{"type" => "text", "text" => text, "styles" => %{"bold" => true}}],
      "children" => children
    }
  end

  test "keeps headings, lists and nesting; drops styles" do
    blocks = [
      block("heading", "Act one", %{"level" => 2}),
      block("paragraph", "The party met a ghost."),
      block("bulletListItem", "Ann", %{}, [block("bulletListItem", "ran")])
    ]

    assert PlainText.render(blocks) ==
             "## Act one\nThe party met a ghost.\n- Ann\n  - ran"
  end

  test "an empty or missing document is empty text" do
    assert PlainText.render(nil) == ""
    assert PlainText.render([]) == ""
  end

  describe "mentions" do
    @id "0b0c7f0e-8d1d-4a43-9f5f-3f7d1f1e2a11"
    @other "1b0c7f0e-8d1d-4a43-9f5f-3f7d1f1e2a11"

    defp mentions,
      do: [
        %{
          "id" => "m",
          "type" => "paragraph",
          "props" => %{},
          "content" => [
            %{"type" => "mention", "props" => %{"kind" => "session", "id" => @id}},
            %{"type" => "text", "text" => " and ", "styles" => %{}},
            %{"type" => "mention", "props" => %{"kind" => "note", "id" => @other}}
          ],
          "children" => []
        }
      ]

    test "names come from the labels, and an unnamed entry is restricted" do
      labels = %{{"session", @id} => "Session 2"}

      assert PlainText.render(mentions(), labels: labels) ==
               "[@Session 2](atlas-entry:session:#{@id}) and " <>
                 "[@Restricted entry](atlas-entry:note:#{@other})"
    end

    test "links can be left out" do
      assert PlainText.render(mentions(),
               labels: %{{"session", @id} => "Session 2"},
               links: false
             ) ==
               "@Session 2 and @Restricted entry"
    end

    test "without labels the name is the kind" do
      assert PlainText.render(mentions()) ==
               "[@session](atlas-entry:session:#{@id}) and [@note](atlas-entry:note:#{@other})"
    end
  end

  describe "for search" do
    test "a mention reads as its bare name" do
      assert PlainText.render(mentions(),
               labels: %{{"session", @id} => "Session 22"},
               links: false,
               at: false
             ) == "Session 22 and Restricted entry"
    end

    test "an image reads as its name and caption only when asked" do
      image = fn props ->
        %{"id" => "i", "type" => "image", "props" => props, "children" => []}
      end

      assert PlainText.render([image.(%{"url" => "atlas-image:x"})]) == ""
      assert PlainText.render([image.(%{})], images: true) == "[image]"

      assert PlainText.render([image.(%{"name" => "keep.png", "caption" => "The keep"})],
               images: true
             ) == "[image: keep.png - The keep]"

      assert PlainText.render([image.(%{"caption" => "The keep"})], images: true) ==
               "[image: The keep]"
    end

    test "a table reads one row per line, with the cells apart" do
      cell = fn text -> [%{"type" => "text", "text" => text, "styles" => %{}}] end

      table = %{
        "id" => "t",
        "type" => "table",
        "props" => %{},
        "content" => %{
          "type" => "tableContent",
          "rows" => [
            %{"cells" => [cell.("Name"), cell.("Role")]},
            %{"cells" => [%{"type" => "tableCell", "content" => cell.("Ann")}, cell.("Thief")]}
          ]
        },
        "children" => []
      }

      assert PlainText.render([table]) == "Name | Role\nAnn | Thief"
    end

    test "flat lists every block with its depth and own text" do
      blocks = [
        %{block("paragraph", "One", %{}, [block("paragraph", "Two")]) | "id" => "a"},
        %{"id" => "d", "type" => "divider", "props" => %{}, "children" => []}
      ]

      assert [
               %{id: "a", type: "paragraph", depth: 0, text: "One"},
               %{id: "b", type: "paragraph", depth: 1, text: "Two"},
               %{id: "d", type: "divider", depth: 0, text: ""}
             ] = PlainText.flat(blocks)
    end
  end
end
