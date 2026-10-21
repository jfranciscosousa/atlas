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
end
