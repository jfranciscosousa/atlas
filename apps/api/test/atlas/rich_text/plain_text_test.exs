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
end
