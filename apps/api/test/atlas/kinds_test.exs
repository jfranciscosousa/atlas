defmodule Atlas.KindsTest do
  use ExUnit.Case, async: true

  alias Atlas.Kinds

  test "the sections of every kind equal the sections its resource declares" do
    for kind <- Kinds.kinds() do
      resource = Kinds.resource(kind)

      assert Enum.sort(Kinds.sections(kind)) == Enum.sort(Atlas.RichText.sections(resource)),
             "#{kind} and #{inspect(resource)} disagree on sections"
    end
  end

  test "a name from a client never becomes a new atom" do
    assert Kinds.fetch("note") == {:ok, :note}
    assert Kinds.fetch("no_such_kind_#{System.unique_integer([:positive])}") == :error
    assert Kinds.fetch(nil) == :error
    assert Kinds.fetch(:no_such_kind) == :error
  end

  test "mentions point to sessions, characters, notes and the world entries" do
    assert Enum.sort(Kinds.mention_names()) ==
             Enum.sort(
               ["character", "note", "session"] ++
                 Enum.map(Atlas.Content.EntrySpec.kinds(), &Atom.to_string/1)
             )
  end

  test "the world entries share one resource" do
    resources = for kind <- Atlas.Content.EntrySpec.kinds(), do: Kinds.resource(kind)
    assert Enum.uniq(resources) == [Atlas.Content.Entry]
    assert Kinds.shared_resource?(Atlas.Content.Entry)
    refute Kinds.shared_resource?(Atlas.Content.Note)
  end

  test "every kind is stored by a resource that has a kind list" do
    for {resource, kinds} <- Kinds.resources(), kind <- kinds do
      assert Kinds.kinds_of(resource) == kinds
      assert kind in Kinds.kinds()
    end
  end
end
