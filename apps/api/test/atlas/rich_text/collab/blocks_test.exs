defmodule Atlas.RichText.Collab.BlocksTest do
  use ExUnit.Case, async: true

  alias Atlas.RichText.Collab.Blocks

  @fixtures "test/support/fixtures/blocknote_yjs.json" |> File.read!() |> Jason.decode!()

  defp doc(update_b64) do
    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, Base.decode64!(update_b64))
    doc
  end

  # The Yjs tree as plain data, so a seeded document can be compared with BlockNote's own.
  defp tree(%Yex.XmlText{} = text) do
    delta =
      for span <- Yex.XmlText.to_delta(text) do
        Map.new(span, fn {k, v} -> {Atom.to_string(k), v} end)
      end

    %{"text" => delta, "attrs" => Yex.XmlText.get_attributes(text)}
  end

  defp tree(%Yex.XmlElement{} = node) do
    %{
      "tag" => Yex.XmlElement.get_tag(node),
      "attrs" => Yex.XmlElement.get_attributes(node),
      "children" => node |> Yex.XmlElement.children() |> Enum.map(&tree/1)
    }
  end

  # JSON has no integers, so compare numbers by value.
  defp numbers(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, numbers(v)} end)
  defp numbers(value) when is_list(value), do: Enum.map(value, &numbers/1)
  defp numbers(value) when is_float(value) and trunc(value) == value, do: trunc(value)
  defp numbers(value), do: value

  test "the prop allow-list matches BlockNote's schema" do
    for {type, props} <- @fixtures["props"] do
      assert Enum.sort(Blocks.props()[type]) == Enum.sort(props), type
    end

    assert Enum.sort(Map.keys(Blocks.props())) == Enum.sort(Map.keys(@fixtures["props"]))
  end

  test "the inline prop allow-list matches BlockNote's schema" do
    assert Enum.sort(Blocks.mention_props()) == Enum.sort(@fixtures["inline"]["mention"])
  end

  for %{"name" => name} = fixture <- @fixtures["cases"] do
    @fixture fixture

    test "#{name}: projects BlockNote's Yjs document to BlockNote's own JSON" do
      assert {:ok, blocks} = Blocks.project(doc(@fixture["update"]))
      assert blocks == @fixture["output"]
      assert {:ok, _} = Blocks.validate(blocks)
    end

    test "#{name}: a seeded document has the tree BlockNote writes" do
      seeded = Blocks.seed(@fixture["output"])
      {:ok, state} = Yex.encode_state_as_update(seeded)
      copy = Yex.Doc.new()
      :ok = Yex.apply_update(copy, state)
      roots = copy |> Yex.Doc.get_array(Blocks.fragment()) |> Yex.Array.to_list()

      assert numbers(Enum.map(roots, &tree/1)) == numbers(@fixture["tree"])
    end

    test "#{name}: a seeded document projects back to what was stored" do
      assert {:ok, blocks} = @fixture["output"] |> Blocks.seed() |> Blocks.project()
      assert blocks == @fixture["output"]
    end
  end

  test "a mention with an unknown attribute or a child is rejected" do
    for {attrs, children} <- [
          {%{"kind" => "note", "id" => "x", "extra" => "y"}, []},
          {%{"kind" => "note", "id" => "x"}, [Yex.XmlTextPrelim.from("a")]}
        ] do
      doc =
        Blocks.seed([%{"id" => "p1", "type" => "paragraph", "content" => [], "children" => []}])

      paragraph =
        doc
        |> Yex.Doc.get_xml_fragment("document-store")
        |> Yex.XmlFragment.first_child()
        |> Yex.XmlElement.first_child()
        |> Yex.XmlElement.first_child()

      :ok = Yex.XmlElement.push(paragraph, Yex.XmlElementPrelim.new("mention", children, attrs))
      assert {:error, _} = Blocks.project(doc)
    end
  end

  test "seeding leaves out props a block does not have" do
    blocks = [
      %{
        "id" => "d1",
        "type" => "divider",
        "props" => %{"textAlignment" => "left"},
        "children" => []
      },
      %{
        "id" => "p1",
        "type" => "paragraph",
        "props" => %{"bogus" => 1},
        "content" => [],
        "children" => []
      }
    ]

    assert {:ok, [%{"props" => %{}}, %{"props" => %{}}]} =
             blocks |> Blocks.seed() |> Blocks.project()
  end

  test "a prop BlockNote left undefined reads as absent" do
    doc =
      Blocks.seed([
        %{"id" => "i1", "type" => "image", "props" => %{"url" => ""}, "children" => []}
      ])

    image =
      doc
      |> Yex.Doc.get_xml_fragment("document-store")
      |> Yex.XmlFragment.first_child()
      |> Yex.XmlElement.first_child()
      |> Yex.XmlElement.first_child()

    :ok = Yex.XmlElement.insert_attribute(image, "name", :undefined)

    assert {:ok, [%{"props" => props}]} = Blocks.project(doc)
    refute Map.has_key?(props, "name")
  end

  describe "editing by block id" do
    defp block(id, text, children \\ []) do
      %{
        "id" => id,
        "type" => "paragraph",
        "props" => %{},
        "content" => [%{"type" => "text", "text" => text, "styles" => %{}}],
        "children" => children
      }
    end

    defp seeded do
      Blocks.seed([block("a", "A", [block("a1", "A1")]), block("b", "B"), block("c", "C")])
    end

    defp texts(doc) do
      {:ok, blocks} = Blocks.project(doc)
      outline(blocks)
    end

    defp outline(blocks) do
      Enum.map(blocks, fn block ->
        text = get_in(block, ["content", Access.at(0), "text"])
        if block["children"] == [], do: text, else: {text, outline(block["children"])}
      end)
    end

    test "insert puts blocks after, before, into or at the end of a block" do
      doc = seeded()
      :ok = Blocks.insert(doc, {:after, "a1"}, [block("x", "X")])
      :ok = Blocks.insert(doc, {:before, "a"}, [block("y", "Y")])
      :ok = Blocks.insert(doc, {:into, "c"}, [block("z", "Z")])
      :ok = Blocks.insert(doc, :end, [block("w", "W")])

      assert texts(doc) == ["Y", {"A", ["A1", "X"]}, "B", {"C", ["Z"]}, "W"]
    end

    test "insert reports a block that does not exist" do
      assert {:error, message} = Blocks.insert(seeded(), {:after, "nope"}, [block("x", "X")])
      assert message =~ ~s(no block has id "nope")
    end

    test "set_content changes one block and keeps its id and nested blocks" do
      doc = seeded()
      {:ok, [a | _]} = Blocks.project(doc)

      :ok =
        Blocks.set_content(doc, %{
          a
          | "type" => "heading",
            "props" => %{"level" => 2},
            "content" => [%{"type" => "text", "text" => "New", "styles" => %{"bold" => true}}]
        })

      assert {:ok, [%{"id" => "a", "type" => "heading", "children" => [%{"id" => "a1"}]}, _, _]} =
               Blocks.project(doc)

      assert texts(doc) == [{"New", ["A1"]}, "B", "C"]
    end

    test "delete removes a block with its nested blocks and an emptied nested group" do
      doc = seeded()
      :ok = Blocks.delete(doc, "a1")
      assert {:ok, [%{"id" => "a", "children" => []}, _, _]} = Blocks.project(doc)

      :ok = Blocks.delete(doc, "a")
      assert texts(doc) == ["B", "C"]
    end

    test "deleting every block leaves one empty paragraph" do
      doc = seeded()
      for id <- ~w(a b c), do: :ok = Blocks.delete(doc, id)

      assert {:ok, [%{"type" => "paragraph", "content" => []}]} = Blocks.project(doc)
    end

    test "move keeps the IDs and the nested blocks" do
      doc = seeded()
      :ok = Blocks.move(doc, "a", {:after, "c"})
      assert texts(doc) == ["B", "C", {"A", ["A1"]}]

      :ok = Blocks.move(doc, "c", {:into, "b"})
      assert texts(doc) == [{"B", ["C"]}, {"A", ["A1"]}]
    end

    test "a block cannot move into itself" do
      assert {:error, message} = Blocks.move(seeded(), "a", {:into, "a1"})
      assert message =~ "itself"
    end

    test "an edit becomes an update that merges into another copy of the document" do
      doc = seeded()
      {:ok, state} = Yex.encode_state_as_update(doc)
      copy = Yex.Doc.new()
      :ok = Yex.apply_update(copy, state)
      {:ok, vector} = Yex.encode_state_vector(copy)

      :ok = Blocks.insert(copy, {:after, "b"}, [block("x", "X")])
      {:ok, update} = Yex.encode_state_as_update(copy, vector)

      :ok = Yex.apply_update(doc, update)
      assert texts(doc) == [{"A", ["A1"]}, "B", "X", "C"]
    end

    test "find and ids look into nested blocks" do
      {:ok, blocks} = Blocks.project(seeded())
      assert Blocks.ids(blocks) == ~w(a a1 b c)
      assert {:ok, %{"id" => "a1"}} = Blocks.find(blocks, "a1")
      assert {:error, _} = Blocks.find(blocks, "nope")
    end
  end
end
