defmodule Atlas.RichText.DocumentTest do
  use ExUnit.Case, async: true

  alias Atlas.RichText.Document
  import Atlas.Fixtures, only: [paragraph: 1]

  @image_id "0b0c7f0e-8d1d-4a43-9f5f-3f7d1f1e2a11"

  defp cast(value), do: Ash.Type.cast_input(Document, value, [])

  test "accepts a native block array with nesting, links, styles and tables" do
    doc = [
      paragraph("hello"),
      %{
        "id" => "h",
        "type" => "heading",
        "props" => %{"level" => 2},
        "content" => [
          %{
            "type" => "link",
            "href" => "https://example.com",
            "content" => [%{"type" => "text", "text" => "x", "styles" => %{"bold" => true}}]
          }
        ],
        "children" => [paragraph("child")]
      },
      %{
        "id" => "t",
        "type" => "table",
        "props" => %{},
        "content" => %{
          "type" => "tableContent",
          "rows" => [%{"cells" => [[%{"type" => "text", "text" => "a", "styles" => %{}}]]}]
        },
        "children" => []
      },
      %{
        "id" => "i",
        "type" => "image",
        "props" => %{"url" => "atlas-image:#{@image_id}", "caption" => nil},
        "children" => []
      }
    ]

    assert {:ok, ^doc} = cast(doc)
    assert Document.image_ids(doc) == [@image_id]
  end

  test "rejects structure the editor never produces" do
    bad = [
      {"not a list", %{"id" => "a"}},
      {"unknown block type", [%{paragraph("x") | "type" => "video"}]},
      {"unknown block key", [Map.put(paragraph("x"), "html", "<b>")]},
      {"javascript link",
       [
         %{
           paragraph("x")
           | "content" => [%{"type" => "link", "href" => "javascript:alert(1)", "content" => []}]
         }
       ]},
      {"non-scalar props", [%{paragraph("x") | "props" => %{"a" => %{"b" => 1}}}]},
      {"unknown style",
       [
         %{
           paragraph("x")
           | "content" => [%{"type" => "text", "text" => "x", "styles" => %{"x" => true}}]
         }
       ]},
      {"url image",
       [%{"id" => "i", "type" => "image", "props" => %{"url" => "https://evil/x.png"}}]},
      {"mention", [%{paragraph("x") | "content" => [%{"type" => "mention", "props" => %{}}]}]}
    ]

    for {label, doc} <- bad do
      assert {:error, _} = cast(doc), label
    end
  end

  test "rejects documents that are too deep or too large" do
    deep = Enum.reduce(1..9, paragraph("leaf"), &%{paragraph("n#{&1}") | "children" => [&2]})
    assert {:error, _} = cast([deep])

    big = [paragraph(String.duplicate("a", 1_000_001))]
    assert {:error, _} = cast(big)
  end
end
