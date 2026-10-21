defmodule Atlas.RichText.Collab.PresenceTest do
  use ExUnit.Case, async: true

  alias Atlas.RichText.Collab.Presence

  @user %{
    id: "9f1c1d2e-0000-4000-8000-000000000001",
    display_name: "Ann",
    email: "ann@example.com"
  }

  test "the colour comes from the palette and is stable for a user ID" do
    assert Presence.color(@user.id) == Presence.color(@user.id)
    assert Presence.color(@user.id) in Presence.palette()

    colors = for n <- 1..200, into: MapSet.new(), do: Presence.color("user-#{n}")
    assert MapSet.size(colors) == length(Presence.palette())
  end

  test "the identity holds the name and colour, and nothing that names the account" do
    identity = Presence.identity(@user)
    assert %{"name" => "Ann", "color" => color, "key" => key} = identity
    assert color == Presence.color(@user.id)
    assert Map.keys(identity) |> Enum.sort() == ["color", "key", "name"]
    refute key =~ @user.id
    refute inspect(identity) =~ "example.com"
  end

  test "the key is the same for one user and differs between users" do
    assert Presence.identity(@user)["key"] == Presence.identity(@user)["key"]
    assert Presence.identity(%{@user | id: "other"})["key"] != Presence.identity(@user)["key"]
  end

  test "a long or blank name is cut or replaced" do
    assert %{"name" => name} =
             Presence.identity(%{@user | display_name: String.duplicate("é", 90)})

    assert String.length(name) == 40
    assert %{"name" => "Someone"} = Presence.identity(%{@user | display_name: "   "})
  end

  test "a state holds the cursor only when there is one" do
    assert Presence.state(@user, nil) |> Map.keys() == ["user"]
    assert %{"cursor" => %{"a" => 1}} = Presence.state(@user, %{"a" => 1})
  end

  test "a channel may send 20 frames in a second, then a new second starts" do
    {window, accepted} =
      Enum.reduce(1..25, {{0, 0}, 0}, fn _, {window, accepted} ->
        case Presence.take(window, 500) do
          {:ok, window} -> {window, accepted + 1}
          :limit -> {window, accepted}
        end
      end)

    assert accepted == 20
    assert :limit = Presence.take(window, 999)
    assert {:ok, {1_000, 1}} = Presence.take(window, 1_000)
  end
end
