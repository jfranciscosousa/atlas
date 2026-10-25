defmodule Atlas.Content.EntryFieldTest do
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Content.{Entry, EntryField}

  setup do
    gm = user()
    campaign = campaign(gm)
    {player, _character} = join_player(campaign, gm)
    outsider = user()
    {:ok, gm: gm, campaign: campaign, player: player, outsider: outsider}
  end

  defp list(actor, campaign, args \\ %{}) do
    EntryField
    |> Ash.Query.for_read(:list, Map.merge(%{campaign_id: campaign.id}, args), actor: actor)
    |> Ash.read!()
  end

  defp create(actor, campaign, params),
    do:
      EntryField
      |> Ash.Changeset.for_create(:create, Map.merge(%{campaign_id: campaign.id}, params),
        actor: actor
      )
      |> Ash.create()

  defp modify(field, action, params, actor),
    do: field |> Ash.Changeset.for_update(action, params, actor: actor) |> Ash.update()

  defp messages({:error, error}) do
    Enum.flat_map(error.errors, fn
      %{message: message} when is_binary(message) -> [message]
      other -> [Exception.message(other)]
    end)
  end

  describe "who may" do
    test "only the GM creates a field", ctx do
      params = %{kind: :faction, label: "Dragonmark", type: :text}
      assert {:ok, field} = create(ctx.gm, ctx.campaign, params)
      assert field.position == 0
      assert field.options == %{}
      refute field.gm_only

      for actor <- [ctx.player, ctx.outsider, nil] do
        assert {:error, %Ash.Error.Forbidden{}} = create(actor, ctx.campaign, params)
      end
    end

    test "only the GM changes, moves, archives and restores", ctx do
      field = entry_field(ctx.gm, ctx.campaign, :faction, "Dragonmark")

      for actor <- [ctx.player, ctx.outsider] do
        for {action, params} <- [
              update: %{label: "Mine"},
              update: %{gm_only: true},
              move: %{position: 0},
              archive: %{},
              restore: %{}
            ] do
          assert {:error, %Ash.Error.Forbidden{}} = modify(field, action, params, actor)
        end
      end

      assert {:ok, %{label: "Mark", gm_only: true}} =
               modify(field, :update, %{label: "Mark", gm_only: true}, ctx.gm)

      assert {:ok, %{archived_at: %DateTime{}} = archived} = modify(field, :archive, %{}, ctx.gm)
      assert {:ok, %{archived_at: nil}} = modify(archived, :restore, %{}, ctx.gm)
    end

    test "a player reads active fields that are not GM-only, and nothing else", ctx do
      open = entry_field(ctx.gm, ctx.campaign, :npc, "Open")
      secret = entry_field(ctx.gm, ctx.campaign, :npc, "True allegiance", :text, %{gm_only: true})
      gone = entry_field(ctx.gm, ctx.campaign, :npc, "Gone")
      modify(gone, :archive, %{}, ctx.gm)

      assert [open.id] == Enum.map(list(ctx.player, ctx.campaign), & &1.id)

      assert [secret.id, open.id] |> Enum.sort() ==
               ctx.gm |> list(ctx.campaign) |> Enum.map(& &1.id) |> Enum.sort()

      assert [] == list(ctx.player, ctx.campaign, %{archived: true})
      assert [gone.id] == Enum.map(list(ctx.gm, ctx.campaign, %{archived: true}), & &1.id)

      assert {:error, %Ash.Error.Invalid{}} = Ash.get(EntryField, secret.id, actor: ctx.player)
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(EntryField, gone.id, actor: ctx.player)
      assert {:ok, _} = Ash.get(EntryField, open.id, actor: ctx.player)
    end

    test "a non-member reads nothing", ctx do
      entry_field(ctx.gm, ctx.campaign, :npc, "Open")
      assert [] == list(ctx.outsider, ctx.campaign)
    end

    test "another campaign has its own fields", ctx do
      other = campaign(ctx.gm, "Dark Sun")
      entry_field(ctx.gm, ctx.campaign, :npc, "Dragonmark")

      entry_field(ctx.gm, other, :npc, "Preserver / Defiler", :select, %{
        choices: ["Preserver", "Defiler"]
      })

      assert ["Dragonmark"] == Enum.map(list(ctx.gm, ctx.campaign), & &1.label)
      assert ["Preserver / Defiler"] == Enum.map(list(ctx.gm, other), & &1.label)

      # The same label may be used again in another campaign.
      assert {:ok, _} = create(ctx.gm, other, %{kind: :npc, label: "Dragonmark", type: :text})
    end
  end

  describe "labels" do
    test "are trimmed, 1 to 60 characters", ctx do
      assert {:ok, %{label: "Dragonmark"}} =
               create(ctx.gm, ctx.campaign, %{kind: :faction, label: "  Dragonmark ", type: :text})

      for label <- ["", "   ", String.duplicate("a", 61)] do
        assert {:error, _} =
                 create(ctx.gm, ctx.campaign, %{kind: :faction, label: label, type: :text})
      end

      assert {:ok, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :faction,
                 label: String.duplicate("a", 60),
                 type: :text
               })
    end

    test "are unique per kind among active fields, ignoring case", ctx do
      entry_field(ctx.gm, ctx.campaign, :faction, "Dragonmark")

      assert {:error, _} =
               result =
               create(ctx.gm, ctx.campaign, %{kind: :faction, label: "dragonMARK", type: :number})

      assert ["is already used by another field of this kind" | _] = messages(result)

      # Another kind may use the label.
      assert {:ok, _} =
               create(ctx.gm, ctx.campaign, %{kind: :npc, label: "Dragonmark", type: :text})
    end

    test "an archived field frees its label, and a restore checks it again", ctx do
      old = entry_field(ctx.gm, ctx.campaign, :faction, "Dragonmark")
      {:ok, archived} = modify(old, :archive, %{}, ctx.gm)

      assert {:ok, new} =
               create(ctx.gm, ctx.campaign, %{kind: :faction, label: "Dragonmark", type: :text})

      assert {:error, _} = result = modify(archived, :restore, %{}, ctx.gm)
      assert ["is already used by another field of this kind" | _] = messages(result)

      {:ok, _} = modify(new, :archive, %{}, ctx.gm)
      assert {:ok, %{archived_at: nil}} = modify(archived, :restore, %{}, ctx.gm)
    end

    test "a rename checks uniqueness too, and may change only the case", ctx do
      entry_field(ctx.gm, ctx.campaign, :faction, "Dragonmark")
      other = entry_field(ctx.gm, ctx.campaign, :faction, "House name")

      assert {:error, _} = modify(other, :update, %{label: "DRAGONMARK"}, ctx.gm)

      assert {:ok, %{label: "House Name"}} =
               modify(other, :update, %{label: "House Name"}, ctx.gm)
    end

    test "must not equal a built-in field of the kind", ctx do
      assert {:error, _} =
               result =
               create(ctx.gm, ctx.campaign, %{kind: :faction, label: "reputation", type: :text})

      assert ["is already a built-in field of Faction" | _] = messages(result)

      # Reputation belongs to factions only.
      assert {:ok, _} =
               create(ctx.gm, ctx.campaign, %{kind: :npc, label: "Reputation", type: :text})

      field = entry_field(ctx.gm, ctx.campaign, :npc, "Origin")
      assert {:error, _} = modify(field, :update, %{label: "Ancestry"}, ctx.gm)
    end
  end

  describe "types and options" do
    test "a select needs choices, an entry field needs a target kind", ctx do
      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{kind: :npc, label: "Path", type: :select})

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Path",
                 type: :select,
                 choices: []
               })

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Path",
                 type: :select,
                 choices: ["A", "a"]
               })

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Path",
                 type: :select,
                 choices: [String.duplicate("a", 61)]
               })

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{kind: :npc, label: "Home", type: :entry})

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Home",
                 type: :text,
                 choices: ["A"]
               })

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Home",
                 type: :text,
                 target_kind: :location
               })

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Home",
                 type: :entry,
                 choices: ["A"],
                 target_kind: :location
               })

      assert {:error, _} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Home",
                 type: :select,
                 choices: ["A"],
                 target_kind: :location
               })

      assert {:ok, %{options: %{"choices" => ["Preserver", "Defiler"]}}} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Path",
                 type: :select,
                 choices: [" Preserver ", "Defiler"]
               })

      assert {:ok, %{options: %{"target_kind" => "location"}}} =
               create(ctx.gm, ctx.campaign, %{
                 kind: :npc,
                 label: "Home",
                 type: :entry,
                 target_kind: :location
               })
    end

    test "the type, the target kind, the kind and the campaign never change", ctx do
      field =
        entry_field(ctx.gm, ctx.campaign, :location, "Kingdom", :entry, %{target_kind: :location})

      for params <- [
            %{type: :text},
            %{kind: :npc},
            %{campaign_id: Ecto.UUID.generate()},
            %{target_kind: :faction},
            %{options: %{}}
          ] do
        assert {:error, _} = modify(field, :update, params, ctx.gm)
      end

      assert {:error, _} = modify(field, :update, %{choices: ["A"]}, ctx.gm)
    end

    test "choices are for a select only", ctx do
      field = entry_field(ctx.gm, ctx.campaign, :npc, "Age", :number)
      assert {:error, _} = modify(field, :update, %{choices: ["A"]}, ctx.gm)
    end
  end

  describe "the choices of a select" do
    setup ctx do
      field =
        entry_field(ctx.gm, ctx.campaign, :npc, "Path", :select, %{
          choices: ["Preserver", "Defiler", "Templar"]
        })

      vex = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{custom_values: %{field.id => "Defiler"}})
      {:ok, field: field, vex: vex}
    end

    defp stored(entry), do: Ash.get!(Entry, entry.id, authorize?: false).custom_fields

    test "adding and reordering choices keeps the values", ctx do
      assert {:ok, %{options: %{"choices" => ["Avangion", "Defiler", "Preserver", "Templar"]}}} =
               modify(
                 ctx.field,
                 :update,
                 %{choices: ["Avangion", "Defiler", "Preserver", "Templar"]},
                 ctx.gm
               )

      assert stored(ctx.vex) == %{ctx.field.id => "Defiler"}
    end

    test "renaming a choice rewrites the stored values", ctx do
      other =
        entry(ctx.gm, ctx.campaign, :npc, "Other", %{
          custom_values: %{ctx.field.id => "Preserver"}
        })

      assert {:ok, _} =
               modify(
                 ctx.field,
                 :update,
                 %{
                   choices: ["Preserver", "Despoiler", "Templar"],
                   renamed_choices: %{"Defiler" => "Despoiler"}
                 },
                 ctx.gm
               )

      assert stored(ctx.vex) == %{ctx.field.id => "Despoiler"}
      assert stored(other) == %{ctx.field.id => "Preserver"}
    end

    test "a chain of renames applies once", ctx do
      assert {:ok, _} =
               modify(
                 ctx.field,
                 :update,
                 %{
                   choices: ["Preserver", "Templar", "Despoiler"],
                   renamed_choices: %{"Defiler" => "Despoiler"}
                 },
                 ctx.gm
               )

      assert {:ok, _} =
               modify(
                 Ash.get!(EntryField, ctx.field.id, actor: ctx.gm),
                 :update,
                 %{
                   choices: ["Preserver", "Templar", "Spoiler"],
                   renamed_choices: %{"Despoiler" => "Spoiler"}
                 },
                 ctx.gm
               )

      assert stored(ctx.vex) == %{ctx.field.id => "Spoiler"}
    end

    test "removing a choice that entries use is refused, and nothing changes", ctx do
      result = modify(ctx.field, :update, %{choices: ["Preserver", "Templar"]}, ctx.gm)
      assert {:error, _} = result
      assert [message] = messages(result)
      assert message =~ ~s(cannot drop "Defiler": 1 entry uses it)

      assert Ash.get!(EntryField, ctx.field.id, actor: ctx.gm).options["choices"] ==
               ["Preserver", "Defiler", "Templar"]

      assert stored(ctx.vex) == %{ctx.field.id => "Defiler"}
    end

    test "an archived entry still counts as a user of a choice", ctx do
      Ash.update!(ctx.vex, %{}, action: :archive, actor: ctx.gm)

      assert {:error, _} =
               modify(ctx.field, :update, %{choices: ["Preserver", "Templar"]}, ctx.gm)
    end

    test "removing a choice that nothing uses works", ctx do
      assert {:ok, %{options: %{"choices" => ["Defiler", "Templar"]}}} =
               modify(ctx.field, :update, %{choices: ["Defiler", "Templar"]}, ctx.gm)
    end

    test "a rename must name an old choice that is gone and a new choice that is listed", ctx do
      for params <- [
            %{
              choices: ["Preserver", "Defiler", "Templar"],
              renamed_choices: %{"Defiler" => "Templar"}
            },
            %{choices: ["Preserver", "Templar", "X"], renamed_choices: %{"Nope" => "X"}},
            %{choices: ["Preserver", "Templar"], renamed_choices: %{"Defiler" => "X"}},
            %{renamed_choices: %{"Defiler" => "X"}}
          ] do
        assert {:error, _} = modify(ctx.field, :update, params, ctx.gm)
      end

      assert stored(ctx.vex) == %{ctx.field.id => "Defiler"}
    end

    test "a rename that only changes the case works", ctx do
      assert {:ok, _} =
               modify(
                 ctx.field,
                 :update,
                 %{
                   choices: ["Preserver", "DEFILER", "Templar"],
                   renamed_choices: %{"Defiler" => "DEFILER"}
                 },
                 ctx.gm
               )

      assert stored(ctx.vex) == %{ctx.field.id => "DEFILER"}
    end
  end

  describe "order" do
    test "a new field goes last in its kind", ctx do
      a = entry_field(ctx.gm, ctx.campaign, :npc, "A")
      b = entry_field(ctx.gm, ctx.campaign, :npc, "B")
      other_kind = entry_field(ctx.gm, ctx.campaign, :item, "C")
      assert {a.position, b.position, other_kind.position} == {0, 1, 0}
    end

    test "move places a field and shifts the others", ctx do
      [a, b, c] = for label <- ~w(A B C), do: entry_field(ctx.gm, ctx.campaign, :npc, label)

      labels = fn ->
        ctx.gm |> list(ctx.campaign, %{kind: :npc}) |> Enum.map(&{&1.label, &1.position})
      end

      assert {:ok, %{position: 0}} = modify(c, :move, %{position: 0}, ctx.gm)
      assert [{"C", 0}, {"A", 1}, {"B", 2}] == labels.()

      assert {:ok, %{position: 2}} = modify(c, :move, %{position: 99}, ctx.gm)
      assert [{"A", 0}, {"B", 1}, {"C", 2}] == labels.()

      assert {:ok, %{position: 1}} = modify(a, :move, %{position: 1}, ctx.gm)
      assert [{"B", 0}, {"A", 1}, {"C", 2}] == labels.()
      _ = b
    end

    test "a negative position is refused, and an archived field has no place", ctx do
      field = entry_field(ctx.gm, ctx.campaign, :npc, "A")
      assert {:error, _} = modify(field, :move, %{position: -1}, ctx.gm)
      {:ok, archived} = modify(field, :archive, %{}, ctx.gm)
      assert {:error, _} = modify(archived, :move, %{position: 0}, ctx.gm)
    end

    test "an archived field leaves the order and a restore puts it last", ctx do
      [a, _b, _c] = for label <- ~w(A B C), do: entry_field(ctx.gm, ctx.campaign, :npc, label)
      {:ok, archived} = modify(a, :archive, %{}, ctx.gm)
      assert ["B", "C"] == ctx.gm |> list(ctx.campaign) |> Enum.map(& &1.label)

      assert {:ok, %{position: 3}} = modify(archived, :restore, %{}, ctx.gm)
      assert ["B", "C", "A"] == ctx.gm |> list(ctx.campaign) |> Enum.map(& &1.label)
    end
  end
end
