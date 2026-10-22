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
end
