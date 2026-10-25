defmodule Atlas.Content.EntryTest do
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Content.{Entry, EntrySpec}

  setup do
    gm = user()
    campaign = campaign(gm)
    {player, _character} = join_player(campaign, gm)
    outsider = user()
    {:ok, gm: gm, campaign: campaign, player: player, outsider: outsider}
  end

  defp list(actor, campaign, args \\ %{}) do
    Entry
    |> Ash.Query.for_read(:list, Map.merge(%{campaign_id: campaign.id}, args), actor: actor)
    |> Ash.read!()
  end

  defp modify(entry, params, actor, action \\ :update_details),
    do: entry |> Ash.Changeset.for_update(action, params, actor: actor) |> Ash.update()

  describe "who writes" do
    test "only the GM creates an entry, and it starts hidden with the default status", ctx do
      for kind <- EntrySpec.kinds() do
        entry = entry(ctx.gm, ctx.campaign, kind, "A #{kind}")
        assert entry.hidden
        assert entry.status == EntrySpec.default_status(kind)
        assert entry.fields == %{}
      end

      for actor <- [ctx.player, ctx.outsider] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Ash.create(
                   Entry,
                   %{campaign_id: ctx.campaign.id, kind: :npc, name: "Nope"},
                   actor: actor
                 )
      end

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(Entry, %{campaign_id: ctx.campaign.id, kind: :npc, name: "Nope"},
                 actor: nil
               )
    end

    test "a player cannot change an entry that is shown, and cannot hide it", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})

      assert {:error, %Ash.Error.Forbidden{}} =
               entry
               |> Ash.Changeset.for_update(:rename, %{name: "Mine"}, actor: ctx.player)
               |> Ash.update()

      for {action, params} <- [
            update_details: %{status: :dead},
            set_hidden: %{hidden: true},
            archive: %{},
            restore: %{}
          ] do
        assert {:error, %Ash.Error.Forbidden{}} = modify(entry, params, ctx.player, action)
      end

      assert Ash.get!(Entry, entry.id, actor: ctx.gm).name == "Vex"
    end

    test "the GM renames, shows, hides, archives and restores", ctx do
      entry = entry(ctx.gm, ctx.campaign, :item, "Sword")
      assert {:ok, %{name: "Blade"}} = modify(entry, %{name: "Blade"}, ctx.gm, :rename)
      assert {:ok, %{hidden: false}} = modify(entry, %{hidden: false}, ctx.gm, :set_hidden)
      assert {:ok, %{hidden: true}} = modify(entry, %{hidden: true}, ctx.gm, :set_hidden)
      assert {:ok, %{archived_at: %DateTime{}}} = modify(entry, %{}, ctx.gm, :archive)
      assert {:ok, %{archived_at: nil}} = modify(entry, %{}, ctx.gm, :restore)
    end

    test "kind and campaign never change after creation", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      assert {:error, _} = modify(entry, %{kind: :location}, ctx.gm)
      assert {:error, _} = modify(entry, %{campaign_id: Ash.UUID.generate()}, ctx.gm)
    end

    test "the name is trimmed, and is 1 to 200 characters", ctx do
      assert %{name: "Vex"} = entry(ctx.gm, ctx.campaign, :npc, "  Vex  ")

      for name <- ["", "   ", String.duplicate("a", 201)] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Ash.create(Entry, %{campaign_id: ctx.campaign.id, kind: :npc, name: name},
                   actor: ctx.gm
                 )
      end
    end

    test "the database accepts only the known kinds", ctx do
      assert_raise Postgrex.Error, ~r/entries_kind_known/, fn ->
        Atlas.Repo.query!(
          "INSERT INTO entries (campaign_id, kind, name, status) VALUES ($1, 'spaceship', 'x', 'active')",
          [Ecto.UUID.dump!(ctx.campaign.id)]
        )
      end
    end
  end

  describe "who reads" do
    test "a hidden entry is readable by the GM alone", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex")

      assert {:ok, _} = Ash.get(Entry, entry.id, actor: ctx.gm)

      for actor <- [ctx.player, ctx.outsider] do
        assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
                 Ash.get(Entry, entry.id, actor: actor)
      end

      assert [%{name: "Vex"}] = list(ctx.gm, ctx.campaign)
      assert [] = list(ctx.player, ctx.campaign)
      assert [] = list(ctx.outsider, ctx.campaign)
      assert {:ok, []} = Ash.read(Entry, actor: nil)
    end

    test "a shown entry is readable by the players, and hiding it again removes it", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})

      assert {:ok, %{name: "Vex"}} = Ash.get(Entry, entry.id, actor: ctx.player)
      assert [%{name: "Vex"}] = list(ctx.player, ctx.campaign)
      assert {:error, _} = Ash.get(Entry, entry.id, actor: ctx.outsider)
      assert [] = list(ctx.outsider, ctx.campaign)

      modify(entry, %{hidden: true}, ctx.gm, :set_hidden)
      assert {:error, _} = Ash.get(Entry, entry.id, actor: ctx.player)
      assert [] = list(ctx.player, ctx.campaign)
    end

    test "an archived entry is readable by the GM alone, even when it was shown", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})
      modify(entry, %{}, ctx.gm, :archive)

      assert {:ok, _} = Ash.get(Entry, entry.id, actor: ctx.gm)
      assert {:error, _} = Ash.get(Entry, entry.id, actor: ctx.player)

      assert [] = list(ctx.gm, ctx.campaign)
      assert [%{name: "Vex"}] = list(ctx.gm, ctx.campaign, %{archived: true})
      assert [] = list(ctx.player, ctx.campaign, %{archived: true})
    end

    test "the GM can list what a player reads, for Preview as player", ctx do
      entry(ctx.gm, ctx.campaign, :npc, "Hidden one")
      entry(ctx.gm, ctx.campaign, :npc, "Shown one", %{shown: true})
      old = entry(ctx.gm, ctx.campaign, :npc, "Old one", %{shown: true})
      modify(old, %{}, ctx.gm, :archive)

      assert ["Hidden one", "Shown one"] ==
               ctx.gm |> list(ctx.campaign) |> Enum.map(& &1.name) |> Enum.sort()

      assert ["Shown one"] ==
               ctx.gm |> list(ctx.campaign, %{as_player: true}) |> Enum.map(& &1.name)

      assert [] = list(ctx.gm, ctx.campaign, %{as_player: true, archived: true})

      # The flag changes nothing for a player.
      assert list(ctx.player, ctx.campaign) == list(ctx.player, ctx.campaign, %{as_player: true})
    end

    test "shown tells whether players read an entry", ctx do
      hidden = entry(ctx.gm, ctx.campaign, :npc, "A")
      shown = entry(ctx.gm, ctx.campaign, :npc, "B", %{shown: true})
      old = entry(ctx.gm, ctx.campaign, :npc, "C", %{shown: true})
      modify(old, %{}, ctx.gm, :archive)

      flags =
        for entry <- [hidden, shown, old],
            do: Ash.get!(Entry, entry.id, actor: ctx.gm, load: [:shown]).shown

      assert flags == [false, true, false]
      assert Ash.get!(Entry, shown.id, actor: ctx.player, load: [:shown]).shown
    end

    test "the list filters by kind and sorts by name", ctx do
      entry(ctx.gm, ctx.campaign, :npc, "Zed")
      entry(ctx.gm, ctx.campaign, :npc, "Ann")
      entry(ctx.gm, ctx.campaign, :location, "Keep")

      assert ["Ann", "Zed"] = ctx.gm |> list(ctx.campaign, %{kind: :npc}) |> Enum.map(& &1.name)
      assert ["Keep"] = ctx.gm |> list(ctx.campaign, %{kind: :location}) |> Enum.map(& &1.name)
      assert 3 = length(list(ctx.gm, ctx.campaign))
    end

    test "a campaign never lists the entries of another", ctx do
      other = campaign(ctx.gm, "Other")
      entry(ctx.gm, other, :npc, "Elsewhere")
      assert [] = list(ctx.gm, ctx.campaign)
    end

    test "a player never receives the secret notes", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})

      save_section!(
        Entry,
        entry.id,
        :secret_notes,
        [paragraph("Vex is a vampire")],
        ctx.gm
      )

      save_section!(Entry, entry.id, :description, [paragraph("A baker")], ctx.gm)

      as_player = Ash.get!(Entry, entry.id, actor: ctx.player)
      assert %Ash.ForbiddenField{} = as_player.secret_notes_json
      assert %Ash.ForbiddenField{} = as_player.secret_notes_revision
      assert [_] = as_player.description_json

      as_gm = Ash.get!(Entry, entry.id, actor: ctx.gm)
      assert [_] = as_gm.secret_notes_json
    end

    test "only the GM writes the description and the secret notes", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})

      for section <- [:description, :secret_notes] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 save_section(Entry, entry.id, section, [paragraph("x")], ctx.player)

        assert {:ok, _} = save_section(Entry, entry.id, section, [paragraph("x")], ctx.gm)
      end
    end
  end

  describe "status" do
    test "a status must belong to the kind", ctx do
      npc = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      assert {:ok, %{status: :dead}} = modify(npc, %{status: :dead}, ctx.gm)
      assert {:error, %Ash.Error.Invalid{}} = modify(npc, %{status: :planned}, ctx.gm)
      assert {:error, %Ash.Error.Invalid{}} = modify(npc, %{status: :bogus}, ctx.gm)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Entry,
                 %{campaign_id: ctx.campaign.id, kind: :plot, name: "P", status: :alive},
                 actor: ctx.gm
               )
    end

    test "every kind accepts each of its statuses", ctx do
      for kind <- EntrySpec.kinds() do
        entry = entry(ctx.gm, ctx.campaign, kind, "A #{kind}")

        for status <- EntrySpec.statuses(kind) do
          assert {:ok, %{status: ^status}} = modify(entry, %{status: status}, ctx.gm)
        end
      end
    end

    test "a plot has a status of planned, active or done", ctx do
      assert %{status: :planned} = entry(ctx.gm, ctx.campaign, :plot, "The heist")
      assert EntrySpec.statuses(:plot) == [:planned, :active, :done]
    end
  end

  describe "fields" do
    test "an entry stores the built-in fields of its kind as text", ctx do
      npc =
        entry(ctx.gm, ctx.campaign, :npc, "Vex", %{
          fields: %{"ancestry" => " Elf ", "gender" => ""}
        })

      assert npc.fields == %{"ancestry" => "Elf"}
    end

    test "a field of another kind, or a value that is not text, is refused", ctx do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Ash.create(
                 Entry,
                 %{campaign_id: ctx.campaign.id, kind: :npc, name: "V", fields: %{"type" => "x"}},
                 actor: ctx.gm
               )

      assert Exception.message(error) =~ "no field type"

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Entry,
                 %{
                   campaign_id: ctx.campaign.id,
                   kind: :npc,
                   name: "V",
                   fields: %{"ancestry" => 7}
                 },
                 actor: ctx.gm
               )

      plot = entry(ctx.gm, ctx.campaign, :plot, "Heist")
      assert {:error, %Ash.Error.Invalid{}} = modify(plot, %{fields: %{"type" => "x"}}, ctx.gm)
    end

    test "a field has a length limit, and a faction's reputation may be longer", ctx do
      npc = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      long = String.duplicate("a", 201)

      assert {:error, %Ash.Error.Invalid{}} =
               modify(npc, %{fields: %{"ancestry" => long}}, ctx.gm)

      faction = entry(ctx.gm, ctx.campaign, :faction, "Guild")
      reputation = String.duplicate("b", 500)

      assert {:ok, %{fields: %{"reputation" => ^reputation}}} =
               modify(faction, %{fields: %{"reputation" => reputation}}, ctx.gm)

      assert {:error, %Ash.Error.Invalid{}} =
               modify(faction, %{fields: %{"reputation" => reputation <> "c"}}, ctx.gm)
    end

    test "an update merges the fields, and a blank value clears one", ctx do
      npc = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{fields: %{"ancestry" => "Elf"}})

      assert {:ok, npc} = modify(npc, %{fields: %{"gender" => "Female"}}, ctx.gm)
      assert npc.fields == %{"ancestry" => "Elf", "gender" => "Female"}

      assert {:ok, npc} = modify(npc, %{fields: %{"ancestry" => "  "}}, ctx.gm)
      assert npc.fields == %{"gender" => "Female"}

      assert {:ok, npc} = modify(npc, %{status: :dead}, ctx.gm)
      assert npc.fields == %{"gender" => "Female"}
    end

    test "players read the reputation of a shown faction, and the GM writes it", ctx do
      faction =
        entry(ctx.gm, ctx.campaign, :faction, "Guild", %{
          shown: true,
          fields: %{"reputation" => "Friendly"}
        })

      assert %{fields: %{"reputation" => "Friendly"}} =
               Ash.get!(Entry, faction.id, actor: ctx.player)

      assert {:error, %Ash.Error.Forbidden{}} =
               modify(faction, %{fields: %{"reputation" => "Hostile"}}, ctx.player)

      assert {:ok, %{fields: %{"reputation" => "Hostile"}}} =
               modify(faction, %{fields: %{"reputation" => "Hostile"}}, ctx.gm)
    end

    test "the fields of one kind are listed in one place" do
      assert EntrySpec.fields(:npc) |> Enum.map(& &1.key) == ["ancestry", "gender"]
      assert EntrySpec.fields(:location) |> Enum.map(& &1.key) == ["type"]
      assert EntrySpec.fields(:faction) |> Enum.map(& &1.key) == ["type", "reputation"]
      assert EntrySpec.fields(:item) |> Enum.map(& &1.key) == ["type"]
      assert EntrySpec.fields(:creature) |> Enum.map(& &1.key) == ["type", "source"]
      assert EntrySpec.fields(:plot) == []
    end
  end

  describe "parent location" do
    test "a location may sit inside another location", ctx do
      realm = entry(ctx.gm, ctx.campaign, :location, "Realm")
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep", %{parent_id: realm.id})
      assert keep.parent_id == realm.id

      assert %{parent_name: "Realm"} =
               Ash.get!(Entry, keep.id, actor: ctx.gm, load: [:parent_name])

      assert {:ok, %{parent_id: nil}} = modify(keep, %{parent_id: nil}, ctx.gm)
    end

    test "only a location has a parent", ctx do
      realm = entry(ctx.gm, ctx.campaign, :location, "Realm")

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Entry,
                 %{campaign_id: ctx.campaign.id, kind: :npc, name: "V", parent_id: realm.id},
                 actor: ctx.gm
               )

      item = entry(ctx.gm, ctx.campaign, :item, "Ring")
      assert {:error, %Ash.Error.Invalid{}} = modify(item, %{parent_id: realm.id}, ctx.gm)
    end

    test "the parent is a location, not another kind", ctx do
      npc = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep")
      assert {:error, %Ash.Error.Invalid{}} = modify(keep, %{parent_id: npc.id}, ctx.gm)
    end

    test "the parent belongs to the same campaign", ctx do
      other = campaign(ctx.gm, "Other")
      far = entry(ctx.gm, other, :location, "Far away")
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep")
      assert {:error, %Ash.Error.Invalid{}} = modify(keep, %{parent_id: far.id}, ctx.gm)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Entry,
                 %{campaign_id: ctx.campaign.id, kind: :location, name: "K", parent_id: far.id},
                 actor: ctx.gm
               )
    end

    test "the parent must exist and must not be archived", ctx do
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep")

      assert {:error, %Ash.Error.Invalid{}} =
               modify(keep, %{parent_id: Ash.UUID.generate()}, ctx.gm)

      realm = entry(ctx.gm, ctx.campaign, :location, "Realm")
      modify(realm, %{}, ctx.gm, :archive)
      assert {:error, %Ash.Error.Invalid{}} = modify(keep, %{parent_id: realm.id}, ctx.gm)
    end

    test "a location is not its own parent, and no cycle is possible", ctx do
      a = entry(ctx.gm, ctx.campaign, :location, "A")
      b = entry(ctx.gm, ctx.campaign, :location, "B", %{parent_id: a.id})
      c = entry(ctx.gm, ctx.campaign, :location, "C", %{parent_id: b.id})

      assert {:error, %Ash.Error.Invalid{} = error} = modify(a, %{parent_id: a.id}, ctx.gm)
      assert Exception.message(error) =~ "own parent"
      assert {:error, %Ash.Error.Invalid{}} = modify(a, %{parent_id: b.id}, ctx.gm)
      assert {:error, %Ash.Error.Invalid{} = error} = modify(a, %{parent_id: c.id}, ctx.gm)
      assert Exception.message(error) =~ "own locations"

      # Moving down the tree stays possible.
      assert {:ok, _} = modify(c, %{parent_id: a.id}, ctx.gm)
    end

    test "the database refuses a parent on another kind and a self-parent", ctx do
      npc = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep")

      assert_raise Postgrex.Error, ~r/entries_parent_is_a_location/, fn ->
        Atlas.Repo.query!("UPDATE entries SET parent_id = $1 WHERE id = $2", [
          Ecto.UUID.dump!(keep.id),
          Ecto.UUID.dump!(npc.id)
        ])
      end

      assert_raise Postgrex.Error, ~r/entries_parent_is_a_location/, fn ->
        Atlas.Repo.query!("UPDATE entries SET parent_id = id WHERE id = $1", [
          Ecto.UUID.dump!(keep.id)
        ])
      end
    end

    test "parent_shown tells the GM whether players read the parent", ctx do
      realm = entry(ctx.gm, ctx.campaign, :location, "Realm")
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep", %{parent_id: realm.id, shown: true})
      loose = entry(ctx.gm, ctx.campaign, :location, "Loose", %{shown: true})

      shown = fn entry, actor ->
        Ash.get!(Entry, entry.id, actor: actor, load: [:parent_shown]).parent_shown
      end

      refute shown.(keep, ctx.gm)
      assert shown.(loose, ctx.gm)

      modify(realm, %{hidden: false}, ctx.gm, :set_hidden)
      assert shown.(keep, ctx.gm)
      assert shown.(keep, ctx.player)

      modify(realm, %{hidden: true}, ctx.gm, :set_hidden)
      assert %Ash.ForbiddenField{} = shown.(keep, ctx.player)
    end

    test "a player gets the parent only when the parent is shown too", ctx do
      realm = entry(ctx.gm, ctx.campaign, :location, "Secret realm")
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep", %{parent_id: realm.id, shown: true})

      seen = Ash.get!(Entry, keep.id, actor: ctx.player, load: [:parent_name])
      assert %Ash.ForbiddenField{} = seen.parent_id
      assert %Ash.ForbiddenField{} = seen.parent_name

      modify(realm, %{hidden: false}, ctx.gm, :set_hidden)
      seen = Ash.get!(Entry, keep.id, actor: ctx.player, load: [:parent_name])
      assert seen.parent_id == realm.id
      assert seen.parent_name == "Secret realm"

      modify(realm, %{}, ctx.gm, :archive)
      seen = Ash.get!(Entry, keep.id, actor: ctx.player, load: [:parent_name])
      assert %Ash.ForbiddenField{} = seen.parent_name
    end
  end

  describe "image" do
    test "an image ID must name an image that exists", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Entry,
                 %{
                   campaign_id: ctx.campaign.id,
                   kind: :npc,
                   name: "V",
                   image_id: Ash.UUID.generate()
                 },
                 actor: ctx.gm
               )

      npc = entry(ctx.gm, ctx.campaign, :npc, "Vex")

      assert {:error, %Ash.Error.Invalid{}} =
               modify(npc, %{image_id: Ash.UUID.generate()}, ctx.gm)
    end
  end
end
