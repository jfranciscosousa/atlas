defmodule Atlas.Content.EntryCustomValuesTest do
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Content.{Entry, EntryField}

  setup do
    gm = user()
    campaign = campaign(gm)
    {player, _character} = join_player(campaign, gm)

    mark = entry_field(gm, campaign, :faction, "Dragonmark")
    population = entry_field(gm, campaign, :location, "Population", :number)
    kingdom = entry_field(gm, campaign, :location, "Kingdom", :entry, %{target_kind: :location})

    allegiance =
      entry_field(gm, campaign, :npc, "True allegiance", :entry, %{
        target_kind: :faction,
        gm_only: true
      })

    path = entry_field(gm, campaign, :npc, "Path", :select, %{choices: ["Preserver", "Defiler"]})
    undead = entry_field(gm, campaign, :npc, "Undead", :boolean)

    {:ok,
     gm: gm,
     campaign: campaign,
     player: player,
     mark: mark,
     population: population,
     kingdom: kingdom,
     allegiance: allegiance,
     path: path,
     undead: undead}
  end

  defp modify(entry, values, actor),
    do:
      entry
      |> Ash.Changeset.for_update(:update_details, %{custom_values: values}, actor: actor)
      |> Ash.update()

  defp values(entry, actor) do
    Entry
    |> Ash.get!(entry.id, actor: actor, load: [:custom_values])
    |> Map.fetch!(:custom_values)
    |> Map.new(&{&1.label, &1.value})
  end

  defp stored(entry), do: Ash.get!(Entry, entry.id, authorize?: false).custom_fields

  defp message({:error, error}),
    do: error |> Map.fetch!(:errors) |> Enum.map_join(" ", & &1.message)

  describe "writing" do
    test "create takes values, and they are stored by field ID", ctx do
      cannith =
        entry(ctx.gm, ctx.campaign, :faction, "House Cannith", %{
          custom_values: %{ctx.mark.id => "  Mark of Making "}
        })

      assert stored(cannith) == %{ctx.mark.id => "Mark of Making"}
    end

    test "text is trimmed and at most 500 characters", ctx do
      f = entry(ctx.gm, ctx.campaign, :faction, "F")
      assert {:error, _} = modify(f, %{ctx.mark.id => String.duplicate("a", 501)}, ctx.gm)
      assert {:ok, _} = modify(f, %{ctx.mark.id => String.duplicate("a", 500)}, ctx.gm)
      assert {:error, _} = modify(f, %{ctx.mark.id => 5}, ctx.gm)
      assert {:error, _} = modify(f, %{ctx.mark.id => true}, ctx.gm)
    end

    test "number is a number", ctx do
      l = entry(ctx.gm, ctx.campaign, :location, "Sharn")
      assert {:ok, _} = modify(l, %{ctx.population.id => 2_000_000}, ctx.gm)
      assert stored(l) == %{ctx.population.id => 2_000_000}
      assert {:ok, _} = modify(l, %{ctx.population.id => 3.5}, ctx.gm)
      assert stored(l) == %{ctx.population.id => 3.5}
      assert {:ok, _} = modify(l, %{ctx.population.id => "42"}, ctx.gm)
      assert stored(l) == %{ctx.population.id => 42}
      assert {:ok, _} = modify(l, %{ctx.population.id => 0}, ctx.gm)
      assert stored(l) == %{ctx.population.id => 0}

      for bad <- ["many", "1e999999", true, [1], %{}, 1.0e20] do
        assert {:error, _} = modify(l, %{ctx.population.id => bad}, ctx.gm)
      end

      assert stored(l) == %{ctx.population.id => 0}
    end

    test "boolean is true or false, and false is a value", ctx do
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      assert {:ok, _} = modify(v, %{ctx.undead.id => false}, ctx.gm)
      assert stored(v) == %{ctx.undead.id => false}
      assert {:ok, _} = modify(v, %{ctx.undead.id => "true"}, ctx.gm)
      assert stored(v) == %{ctx.undead.id => true}

      for bad <- ["yes", 1, 0, "maybe"] do
        assert {:error, _} = modify(v, %{ctx.undead.id => bad}, ctx.gm)
      end
    end

    test "select is one of the choices", ctx do
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      assert {:ok, _} = modify(v, %{ctx.path.id => "Defiler"}, ctx.gm)
      assert stored(v) == %{ctx.path.id => "Defiler"}

      for bad <- ["defiler", "Templar", 1, true] do
        assert {:error, _} = modify(v, %{ctx.path.id => bad}, ctx.gm)
      end
    end

    test "an entry field takes a non-archived entry of the target kind in the same campaign",
         ctx do
      aundair = entry(ctx.gm, ctx.campaign, :location, "Aundair")
      sharn = entry(ctx.gm, ctx.campaign, :location, "Sharn")
      npc = entry(ctx.gm, ctx.campaign, :npc, "Vex")

      assert {:ok, _} = modify(sharn, %{ctx.kingdom.id => aundair.id}, ctx.gm)
      assert stored(sharn) == %{ctx.kingdom.id => aundair.id}

      # A hidden entry is a fine target: the GM reads it.
      assert aundair.hidden

      other = campaign(ctx.gm, "Dark Sun")
      foreign = entry(ctx.gm, other, :location, "Tyr")
      archived = entry(ctx.gm, ctx.campaign, :location, "Old")
      Ash.update!(archived, %{}, action: :archive, actor: ctx.gm)

      for bad <- [npc.id, foreign.id, archived.id, Ecto.UUID.generate(), "not-an-id", 5] do
        assert {:error, _} = modify(sharn, %{ctx.kingdom.id => bad}, ctx.gm)
      end

      assert stored(sharn) == %{ctx.kingdom.id => aundair.id}
    end

    test "an empty value removes the key, and the other values stay", ctx do
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      {:ok, _} = modify(v, %{ctx.path.id => "Defiler", ctx.undead.id => false}, ctx.gm)

      for empty <- [nil, "", "   "] do
        {:ok, _} = modify(v, %{ctx.path.id => "Preserver"}, ctx.gm)
        assert {:ok, _} = modify(v, %{ctx.path.id => empty}, ctx.gm)
        assert stored(v) == %{ctx.undead.id => false}
      end
    end

    test "an ID must belong to an active field of the kind in the campaign", ctx do
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex")

      other = campaign(ctx.gm, "Dark Sun")
      foreign = entry_field(ctx.gm, other, :npc, "Foreign")

      for id <- [ctx.mark.id, ctx.population.id, foreign.id, Ecto.UUID.generate(), "label"] do
        assert {:error, _} = modify(v, %{id => "x"}, ctx.gm)
      end

      Ash.update!(ctx.path, %{}, action: :archive, actor: ctx.gm)
      assert {:error, _} = modify(v, %{ctx.path.id => "Defiler"}, ctx.gm)
      assert stored(v) == %{}
    end

    test "a failed value changes nothing", ctx do
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex")

      assert {:error, _} =
               modify(v, %{ctx.path.id => "Defiler", ctx.undead.id => "maybe"}, ctx.gm)

      assert stored(v) == %{}
    end

    test "only the GM writes values", ctx do
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})
      assert {:error, %Ash.Error.Forbidden{}} = modify(v, %{ctx.path.id => "Defiler"}, ctx.player)
    end

    test "values have no place in the stored entry for a client", _ctx do
      refute Ash.Resource.Info.public_attribute(Entry, :custom_fields)
      assert Ash.Resource.Info.public_calculation(Entry, :custom_values)
    end
  end

  describe "reading" do
    test "a custom field with no value reads as nil, in order", ctx do
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      view = Ash.get!(Entry, v.id, actor: ctx.gm, load: [:custom_values]).custom_values

      assert ["Path", "Undead", "True allegiance"] |> Enum.sort() ==
               view |> Enum.map(& &1.label) |> Enum.sort()

      assert Enum.all?(view, &is_nil(&1.value))

      assert %{
               type: "select",
               choices: ["Preserver", "Defiler"],
               target_kind: nil,
               gm_only: false
             } =
               Enum.find(view, &(&1.label == "Path"))

      assert %{type: "entry", choices: nil, target_kind: "faction", gm_only: true} =
               Enum.find(view, &(&1.label == "True allegiance"))
    end

    test "a player never gets a GM-only field or its value", ctx do
      cannith = entry(ctx.gm, ctx.campaign, :faction, "House Cannith", %{shown: true})
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})
      {:ok, _} = modify(v, %{ctx.allegiance.id => cannith.id, ctx.path.id => "Defiler"}, ctx.gm)

      assert %{"True allegiance" => %{label: "House Cannith"}, "Path" => "Defiler"} =
               values(v, ctx.gm)

      assert %{"Path" => "Defiler"} = player_view = values(v, ctx.player)
      refute Map.has_key?(player_view, "True allegiance")

      assert [%{id: id}] =
               Ash.get!(Entry, v.id, actor: ctx.player, load: [:custom_values]).custom_values
               |> Enum.filter(&(&1.label == "Path"))

      assert id == ctx.path.id

      # The player's response holds neither the ID nor the label nor the target.
      json =
        Ash.get!(Entry, v.id, actor: ctx.player, load: [:custom_values]).custom_values
        |> Jason.encode!()

      refute json =~ ctx.allegiance.id
      refute json =~ cannith.id
      refute json =~ "allegiance"
    end

    test "an entry value that points to an entry the reader cannot read is restricted", ctx do
      aundair = entry(ctx.gm, ctx.campaign, :location, "Aundair")
      sharn = entry(ctx.gm, ctx.campaign, :location, "Sharn", %{shown: true})
      {:ok, _} = modify(sharn, %{ctx.kingdom.id => aundair.id}, ctx.gm)

      assert %{label: "Aundair", restricted: false, shown: false, id: id} =
               values(sharn, ctx.gm)["Kingdom"]

      assert id == aundair.id

      restricted = values(sharn, ctx.player)["Kingdom"]

      assert %{
               label: "Restricted entry",
               restricted: true,
               id: nil,
               shown: false,
               kind: "location"
             } = restricted

      refute Jason.encode!(restricted) =~ "Aundair"
      refute Jason.encode!(restricted) =~ aundair.id

      Ash.update!(aundair, %{hidden: false}, action: :set_hidden, actor: ctx.gm)

      assert %{label: "Aundair", restricted: false, shown: true} =
               values(sharn, ctx.player)["Kingdom"]

      Ash.update!(Ash.get!(Entry, aundair.id, actor: ctx.gm), %{hidden: true},
        action: :set_hidden,
        actor: ctx.gm
      )

      assert %{label: "Restricted entry", id: nil} = values(sharn, ctx.player)["Kingdom"]
    end

    test "an archived target reads as a deleted entry for the GM, and restricted for a player",
         ctx do
      aundair = entry(ctx.gm, ctx.campaign, :location, "Aundair", %{shown: true})
      sharn = entry(ctx.gm, ctx.campaign, :location, "Sharn", %{shown: true})
      {:ok, _} = modify(sharn, %{ctx.kingdom.id => aundair.id}, ctx.gm)
      Ash.update!(aundair, %{}, action: :archive, actor: ctx.gm)

      assert %{label: "Deleted entry", shown: false} = values(sharn, ctx.gm)["Kingdom"]
      assert %{label: "Restricted entry", id: nil} = values(sharn, ctx.player)["Kingdom"]
    end

    test "an archived field hides its values, and a restore shows them again", ctx do
      cannith = entry(ctx.gm, ctx.campaign, :faction, "House Cannith", %{shown: true})
      {:ok, _} = modify(cannith, %{ctx.mark.id => "Mark of Making"}, ctx.gm)
      assert %{"Dragonmark" => "Mark of Making"} = values(cannith, ctx.player)

      archived = Ash.update!(ctx.mark, %{}, action: :archive, actor: ctx.gm)
      assert values(cannith, ctx.gm) == %{}
      assert values(cannith, ctx.player) == %{}
      assert stored(cannith) == %{ctx.mark.id => "Mark of Making"}

      Ash.update!(archived, %{}, action: :restore, actor: ctx.gm)
      assert %{"Dragonmark" => "Mark of Making"} = values(cannith, ctx.gm)
      assert %{"Dragonmark" => "Mark of Making"} = values(cannith, ctx.player)
    end

    test "the fields of another campaign never show", ctx do
      other = campaign(ctx.gm, "Dark Sun")
      entry_field(ctx.gm, other, :faction, "Templar order")
      f = entry(ctx.gm, ctx.campaign, :faction, "F")
      assert ["Dragonmark"] == f |> values(ctx.gm) |> Map.keys()
    end

    test "renaming a field changes no data", ctx do
      f = entry(ctx.gm, ctx.campaign, :faction, "F")
      {:ok, _} = modify(f, %{ctx.mark.id => "Mark"}, ctx.gm)
      Ash.update!(ctx.mark, %{label: "Mark of the house"}, action: :update, actor: ctx.gm)
      assert stored(f) == %{ctx.mark.id => "Mark"}
      assert %{"Mark of the house" => "Mark"} = values(f, ctx.gm)
    end

    test "custom values do not take part in search", ctx do
      f = entry(ctx.gm, ctx.campaign, :faction, "F", %{shown: true})
      {:ok, _} = modify(f, %{ctx.mark.id => "Zzyzx"}, ctx.gm)

      result =
        Atlas.Search.Request
        |> Ash.ActionInput.for_action(:search, %{query: "zzyzx"}, actor: ctx.gm)
        |> Ash.run_action!()

      assert result.hits == []
    end
  end

  describe "filter" do
    defp names(actor, campaign, args) do
      Entry
      |> Ash.Query.for_read(:list, Map.merge(%{campaign_id: campaign.id}, args), actor: actor)
      |> Ash.read()
      |> case do
        {:ok, entries} -> entries |> Enum.map(& &1.name) |> Enum.sort()
        {:error, _} = error -> error
      end
    end

    setup ctx do
      aundair = entry(ctx.gm, ctx.campaign, :location, "Aundair", %{shown: true})
      breland = entry(ctx.gm, ctx.campaign, :location, "Breland", %{shown: true})

      for {name, kingdom, population, shown} <- [
            {"Fairhaven", aundair, 300_000, true},
            {"Wroat", aundair, 3.5, true},
            {"Sharn", breland, 3, true},
            {"Secret town", aundair, 3, false}
          ] do
        l = entry(ctx.gm, ctx.campaign, :location, name, %{shown: shown})

        {:ok, _} =
          modify(l, %{ctx.kingdom.id => kingdom.id, ctx.population.id => population}, ctx.gm)
      end

      {:ok, aundair: aundair, breland: breland}
    end

    test "an entry value", ctx do
      args = %{custom_field_id: ctx.kingdom.id, custom_field_value: ctx.aundair.id}
      assert ["Fairhaven", "Secret town", "Wroat"] == names(ctx.gm, ctx.campaign, args)
      assert ["Fairhaven", "Wroat"] == names(ctx.player, ctx.campaign, args)

      assert ["Sharn"] ==
               names(ctx.gm, ctx.campaign, %{args | custom_field_value: ctx.breland.id})

      assert ["Fairhaven", "Wroat"] ==
               names(ctx.gm, ctx.campaign, Map.put(args, :as_player, true))
    end

    test "a number compares as a number", ctx do
      id = ctx.population.id

      assert ["Secret town", "Sharn"] ==
               names(ctx.gm, ctx.campaign, %{custom_field_id: id, custom_field_value: "3"})

      assert ["Secret town", "Sharn"] ==
               names(ctx.gm, ctx.campaign, %{custom_field_id: id, custom_field_value: "3.0"})

      assert ["Wroat"] ==
               names(ctx.gm, ctx.campaign, %{custom_field_id: id, custom_field_value: "3.5"})

      assert [] == names(ctx.gm, ctx.campaign, %{custom_field_id: id, custom_field_value: "4"})

      assert {:error, _} =
               names(ctx.gm, ctx.campaign, %{custom_field_id: id, custom_field_value: "many"})
    end

    test "text ignores case, boolean and select compare as stored", ctx do
      a = entry(ctx.gm, ctx.campaign, :faction, "A")
      b = entry(ctx.gm, ctx.campaign, :faction, "B")
      {:ok, _} = modify(a, %{ctx.mark.id => "Mark of Making"}, ctx.gm)
      {:ok, _} = modify(b, %{ctx.mark.id => "Mark of Healing"}, ctx.gm)

      assert ["A"] ==
               names(ctx.gm, ctx.campaign, %{
                 custom_field_id: ctx.mark.id,
                 custom_field_value: " mark OF making "
               })

      v = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      w = entry(ctx.gm, ctx.campaign, :npc, "Wen")
      {:ok, _} = modify(v, %{ctx.path.id => "Defiler", ctx.undead.id => true}, ctx.gm)
      {:ok, _} = modify(w, %{ctx.path.id => "Preserver", ctx.undead.id => false}, ctx.gm)

      assert ["Vex"] ==
               names(ctx.gm, ctx.campaign, %{
                 custom_field_id: ctx.path.id,
                 custom_field_value: "Defiler"
               })

      assert ["Wen"] ==
               names(ctx.gm, ctx.campaign, %{
                 custom_field_id: ctx.undead.id,
                 custom_field_value: "false"
               })

      assert {:error, _} =
               names(ctx.gm, ctx.campaign, %{
                 custom_field_id: ctx.path.id,
                 custom_field_value: "Templar"
               })
    end

    test "both arguments come together", ctx do
      assert {:error, _} = names(ctx.gm, ctx.campaign, %{custom_field_id: ctx.kingdom.id})
      assert {:error, _} = names(ctx.gm, ctx.campaign, %{custom_field_value: "x"})
    end

    test "a player cannot filter by a GM-only field, and learns nothing from the error", ctx do
      cannith = entry(ctx.gm, ctx.campaign, :faction, "House Cannith", %{shown: true})
      v = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})
      {:ok, _} = modify(v, %{ctx.allegiance.id => cannith.id}, ctx.gm)

      args = %{custom_field_id: ctx.allegiance.id, custom_field_value: cannith.id}
      assert ["Vex"] == names(ctx.gm, ctx.campaign, args)

      gm_only_error = names(ctx.player, ctx.campaign, args)

      missing_error =
        names(ctx.player, ctx.campaign, %{args | custom_field_id: Ecto.UUID.generate()})

      assert {:error, _} = gm_only_error
      assert message(gm_only_error) == message(missing_error)

      # Preview as player reads fields as a player does.
      assert {:error, _} = names(ctx.gm, ctx.campaign, Map.put(args, :as_player, true))
    end

    test "a field of another campaign or an archived field is refused", ctx do
      other = campaign(ctx.gm, "Dark Sun")

      assert {:error, _} =
               names(ctx.gm, other, %{
                 custom_field_id: ctx.kingdom.id,
                 custom_field_value: ctx.aundair.id
               })

      Ash.update!(ctx.kingdom, %{}, action: :archive, actor: ctx.gm)

      assert {:error, _} =
               names(ctx.gm, ctx.campaign, %{
                 custom_field_id: ctx.kingdom.id,
                 custom_field_value: ctx.aundair.id
               })
    end

    test "an entry value that a player cannot read is refused", ctx do
      hidden = entry(ctx.gm, ctx.campaign, :location, "Hidden kingdom")
      args = %{custom_field_id: ctx.kingdom.id, custom_field_value: hidden.id}
      assert [] == names(ctx.gm, ctx.campaign, args)
      assert {:error, _} = names(ctx.player, ctx.campaign, args)
    end

    test "the kind argument works with the filter", ctx do
      args = %{custom_field_id: ctx.kingdom.id, custom_field_value: ctx.aundair.id, kind: :npc}
      assert [] == names(ctx.gm, ctx.campaign, args)
    end
  end

  test "fields are listed through the resource too", ctx do
    assert 6 ==
             EntryField
             |> Ash.Query.for_read(:list, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)
             |> Ash.read!()
             |> length()
  end
end
