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

  defp modify(entry, params, actor, action),
    do: entry |> Ash.Changeset.for_update(action, params, actor: actor) |> Ash.update()

  describe "who writes" do
    test "only the GM creates an entry, and it starts hidden", ctx do
      for kind <- EntrySpec.kinds() do
        entry = entry(ctx.gm, ctx.campaign, kind, "A #{kind}")
        assert entry.hidden
        assert entry.kind == kind
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

    test "an entry has no metadata to write: the text carries every detail", ctx do
      for params <- [
            %{status: :dead},
            %{fields: %{"ancestry" => "Elf"}},
            %{parent_id: Ash.UUID.generate()},
            %{image_id: Ash.UUID.generate()}
          ] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Ash.create(
                   Entry,
                   Map.merge(
                     %{campaign_id: ctx.campaign.id, kind: :npc, name: "Vex"},
                     params
                   ),
                   actor: ctx.gm
                 )
      end
    end

    test "a player cannot change an entry that is shown, and cannot hide it", ctx do
      entry = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})

      assert {:error, %Ash.Error.Forbidden{}} =
               entry
               |> Ash.Changeset.for_update(:rename, %{name: "Mine"}, actor: ctx.player)
               |> Ash.update()

      for {action, params} <- [
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
      assert {:error, _} = modify(entry, %{kind: :location}, ctx.gm, :rename)
      assert {:error, _} = modify(entry, %{campaign_id: Ash.UUID.generate()}, ctx.gm, :rename)
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
          "INSERT INTO entries (campaign_id, kind, name) VALUES ($1, 'spaceship', 'x')",
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
end
