defmodule Atlas.Content.EntryRelationTest do
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Content.{Entry, EntryRelation, RelationSpec}

  setup do
    gm = user()
    campaign = campaign(gm)
    {player, character} = join_player(campaign, gm)
    outsider = user()

    guild = entry(gm, campaign, :faction, "Guild", %{shown: true})
    vex = entry(gm, campaign, :npc, "Vex", %{shown: true})

    {:ok,
     gm: gm,
     campaign: campaign,
     player: player,
     character: character,
     outsider: outsider,
     guild: guild,
     vex: vex}
  end

  defp relate(ctx, from, to, relation, actor \\ nil, extra \\ %{}) do
    from_kind = if match?(%Entry{}, from), do: from.kind, else: :character
    to_kind = if match?(%Entry{}, to), do: to.kind, else: :character

    Ash.create(
      EntryRelation,
      Map.merge(
        %{
          campaign_id: ctx.campaign.id,
          from_kind: from_kind,
          from_id: from.id,
          to_kind: to_kind,
          to_id: to.id,
          relation: relation
        },
        extra
      ),
      actor: actor || ctx.gm
    )
  end

  defp relations_of(actor, ctx, entry) do
    EntryRelation
    |> Ash.Query.for_read(:list, %{campaign_id: ctx.campaign.id, end_id: entry.id}, actor: actor)
    |> Ash.Query.load([:from_name, :to_name])
    |> Ash.read!()
  end

  test "the GM relates an NPC to a faction, with a label", ctx do
    assert {:ok, relation} = relate(ctx, ctx.vex, ctx.guild, :member_of, nil, %{label: " staff "})
    assert relation.label == "staff"

    for end_id <- [ctx.vex.id, ctx.guild.id] do
      assert [%{id: id, from_name: "Vex", to_name: "Guild"}] =
               relations_of(ctx.gm, ctx, %{id: end_id})

      assert id == relation.id
    end
  end

  test "a character is an end of a relation", ctx do
    sword = entry(ctx.gm, ctx.campaign, :item, "Sword", %{shown: true})
    assert {:ok, _} = relate(ctx, sword, ctx.character, :held_by)

    assert [%{to_name: "Unnamed character", to_kind: :character}] =
             relations_of(ctx.gm, ctx, sword)

    assert [_] = relations_of(ctx.player, ctx, ctx.character)
  end

  test "only the GM adds and removes a relation", ctx do
    assert {:error, %Ash.Error.Forbidden{}} =
             relate(ctx, ctx.vex, ctx.guild, :member_of, ctx.player)

    # The ends of a non-member are not found, so the request fails before the policy.
    assert {:error, _} = relate(ctx, ctx.vex, ctx.guild, :member_of, ctx.outsider)
    assert [] = relations_of(ctx.gm, ctx, ctx.vex)

    {:ok, relation} = relate(ctx, ctx.vex, ctx.guild, :member_of)

    for actor <- [ctx.player, ctx.outsider] do
      assert {:error, _} = Ash.destroy(relation, actor: actor)
    end

    assert :ok = Ash.destroy(relation, actor: ctx.gm)
    assert [] = relations_of(ctx.gm, ctx, ctx.vex)
  end

  describe "visibility" do
    test "a player reads a relation only when both ends are shown", ctx do
      secret = entry(ctx.gm, ctx.campaign, :npc, "Spy")
      {:ok, shown} = relate(ctx, ctx.vex, ctx.guild, :member_of)
      {:ok, hidden} = relate(ctx, secret, ctx.guild, :member_of)

      assert [%{id: id}] = relations_of(ctx.player, ctx, ctx.guild)
      assert id == shown.id

      assert [] = relations_of(ctx.player, ctx, secret)
      assert [_, _] = relations_of(ctx.gm, ctx, ctx.guild)
      assert {:error, _} = Ash.get(EntryRelation, hidden.id, actor: ctx.player)

      # Showing the other end shows the relation.
      Ash.update!(secret, %{hidden: false}, action: :set_hidden, actor: ctx.gm)
      assert [_, _] = relations_of(ctx.player, ctx, ctx.guild)

      # Hiding either end hides it again.
      Ash.update!(ctx.guild, %{hidden: true}, action: :set_hidden, actor: ctx.gm)
      assert [] = relations_of(ctx.player, ctx, ctx.vex)
      assert [] = relations_of(ctx.player, ctx, ctx.guild)
    end

    test "a relation to an archived entry is invisible to a player", ctx do
      {:ok, _} = relate(ctx, ctx.vex, ctx.guild, :member_of)
      Ash.update!(ctx.vex, %{}, action: :archive, actor: ctx.gm)

      assert [] = relations_of(ctx.player, ctx, ctx.guild)
      assert [_] = relations_of(ctx.gm, ctx, ctx.guild)
    end

    test "a non-member reads no relation", ctx do
      {:ok, _} = relate(ctx, ctx.vex, ctx.guild, :member_of)
      assert [] = relations_of(ctx.outsider, ctx, ctx.guild)
    end

    test "the GM sees whether players read each end", ctx do
      secret = entry(ctx.gm, ctx.campaign, :npc, "Spy")
      {:ok, _} = relate(ctx, secret, ctx.guild, :member_of)
      {:ok, _} = relate(ctx, ctx.vex, ctx.character, :allied_with, nil, %{})

      assert [%{from_shown: false, to_shown: true}] =
               ctx.gm
               |> relations_of(ctx, secret)
               |> Ash.load!([:from_shown, :to_shown], actor: ctx.gm)
    end
  end

  describe "rules" do
    test "a relation joins only the kinds that it allows", ctx do
      keep = entry(ctx.gm, ctx.campaign, :location, "Keep", %{shown: true})
      sword = entry(ctx.gm, ctx.campaign, :item, "Sword", %{shown: true})
      heist = entry(ctx.gm, ctx.campaign, :plot, "Heist", %{shown: true})

      assert {:ok, _} = relate(ctx, ctx.vex, keep, :located_in)
      assert {:ok, _} = relate(ctx, keep, ctx.guild, :headquarters_of)
      assert {:ok, _} = relate(ctx, sword, ctx.vex, :held_by)
      assert {:ok, _} = relate(ctx, heist, ctx.vex, :involves)
      assert {:ok, _} = relate(ctx, heist, keep, :involves)
      assert {:ok, _} = relate(ctx, heist, ctx.character, :involves)

      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, keep, ctx.vex, :member_of)
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, ctx.guild, :headquarters_of)
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, sword, :held_by)
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, heist, :involves)
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, keep, :held_by)
    end

    test "the spec lists every relation of the design" do
      assert RelationSpec.relations() ==
               [
                 :member_of,
                 :located_in,
                 :headquarters_of,
                 :held_by,
                 :allied_with,
                 :enemy_of,
                 :involves
               ]

      refute RelationSpec.allowed?(:made_up, :npc, :npc)
    end

    test "an unknown relation or kind is refused", ctx do
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, ctx.guild, :cousin_of)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 EntryRelation,
                 %{
                   campaign_id: ctx.campaign.id,
                   from_kind: :campaign,
                   from_id: ctx.vex.id,
                   to_kind: :faction,
                   to_id: ctx.guild.id,
                   relation: :member_of
                 },
                 actor: ctx.gm
               )
    end

    test "an end is not related to itself", ctx do
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, ctx.vex, :allied_with)
    end

    test "the stated kind must be the real kind", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 EntryRelation,
                 %{
                   campaign_id: ctx.campaign.id,
                   from_kind: :npc,
                   from_id: ctx.guild.id,
                   to_kind: :faction,
                   to_id: ctx.guild.id,
                   relation: :member_of
                 },
                 actor: ctx.gm
               )
    end

    test "both ends belong to the campaign and are active", ctx do
      other = campaign(ctx.gm, "Other")
      far = entry(ctx.gm, other, :faction, "Far guild")
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, far, :member_of)

      gone = entry(ctx.gm, ctx.campaign, :faction, "Gone")
      Ash.update!(gone, %{}, action: :archive, actor: ctx.gm)
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.vex, gone, :member_of)

      stranger = Ash.UUID.generate()

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 EntryRelation,
                 %{
                   campaign_id: ctx.campaign.id,
                   from_kind: :npc,
                   from_id: ctx.vex.id,
                   to_kind: :faction,
                   to_id: stranger,
                   relation: :member_of
                 },
                 actor: ctx.gm
               )
    end

    test "a relation exists once, and a symmetric one once for a pair", ctx do
      assert {:ok, _} = relate(ctx, ctx.vex, ctx.guild, :member_of)
      assert {:error, %Ash.Error.Invalid{} = error} = relate(ctx, ctx.vex, ctx.guild, :member_of)
      assert Exception.message(error) =~ "already related"

      rival = entry(ctx.gm, ctx.campaign, :faction, "Rivals", %{shown: true})
      assert {:ok, _} = relate(ctx, ctx.guild, rival, :enemy_of)
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, rival, ctx.guild, :enemy_of)
      assert {:error, %Ash.Error.Invalid{}} = relate(ctx, ctx.guild, rival, :enemy_of)

      # The same pair may have another relation, and a directed relation may run both ways.
      assert {:ok, _} = relate(ctx, ctx.guild, rival, :allied_with)
      assert {:ok, _} = relate(ctx, ctx.guild, ctx.vex, :allied_with)
    end

    test "the database refuses a relation to itself", ctx do
      assert_raise Postgrex.Error, ~r/entry_relations_not_itself/, fn ->
        Atlas.Repo.query!(
          "INSERT INTO entry_relations (campaign_id, from_kind, from_id, to_kind, to_id, relation) VALUES ($1, 'npc', $2, 'npc', $2, 'allied_with')",
          [Ecto.UUID.dump!(ctx.campaign.id), Ecto.UUID.dump!(ctx.vex.id)]
        )
      end
    end

    test "the label is optional and at most 100 characters", ctx do
      assert {:ok, %{label: nil}} = relate(ctx, ctx.vex, ctx.guild, :member_of)

      other = entry(ctx.gm, ctx.campaign, :faction, "Other", %{shown: true})

      assert {:error, %Ash.Error.Invalid{}} =
               relate(ctx, ctx.vex, other, :member_of, nil, %{label: String.duplicate("a", 101)})
    end
  end

  test "describe shows both directions from each end", ctx do
    {:ok, _} = relate(ctx, ctx.vex, ctx.guild, :member_of, nil, %{label: "staff"})

    assert %{
             relations: [
               %{
                 direction: :outgoing,
                 text: "member of",
                 label: "staff",
                 other: %{kind: :faction, name: "Guild"}
               }
             ]
           } = EntryRelation.describe(ctx.vex, ctx.gm)

    assert %{
             relations: [
               %{
                 direction: :incoming,
                 text: "members",
                 other: %{kind: :npc, name: "Vex"}
               }
             ]
           } = EntryRelation.describe(ctx.guild, ctx.gm)
  end
end
