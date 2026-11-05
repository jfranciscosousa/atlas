defmodule Atlas.Content.EntrySortTest do
  @moduledoc "The `sort` argument of the entry list: name, last edited, last created, last mentioned."
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Campaigns.{PlayerLog, Session}
  alias Atlas.Content.Entry

  setup do
    gm = user()
    campaign = campaign(gm)
    {player, _character} = join_player(campaign, gm)
    {:ok, gm: gm, campaign: campaign, player: player}
  end

  defp names(actor, campaign, args \\ %{}) do
    Entry
    |> Ash.Query.for_read(:list, Map.merge(%{campaign_id: campaign.id}, args), actor: actor)
    |> Ash.read!()
    |> Enum.map(& &1.name)
  end

  defp mention(id),
    do: %{"type" => "mention", "props" => %{"kind" => "npc", "id" => id}}

  defp mentioning(entries),
    do: [
      %{
        "id" => "p1",
        "type" => "paragraph",
        "props" => %{},
        "content" => Enum.map(List.wrap(entries), &mention(&1.id)),
        "children" => []
      }
    ]

  defp list_all(ctx) do
    Entry
    |> Ash.Query.for_read(:list, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)
    |> Ash.read!()
  end

  defp session!(ctx), do: Ash.create!(Session, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)

  defp npc(ctx, name, attrs \\ %{}), do: entry(ctx.gm, ctx.campaign, :npc, name, attrs)

  test "the default order is by name", ctx do
    for name <- ["Cora", "Ash", "Bram"], do: npc(ctx, name)

    assert ["Ash", "Bram", "Cora"] = names(ctx.gm, ctx.campaign)
    assert ["Ash", "Bram", "Cora"] = names(ctx.gm, ctx.campaign, %{sort: :name})
  end

  test "an unknown sort is refused", ctx do
    assert_raise Ash.Error.Invalid, fn -> names(ctx.gm, ctx.campaign, %{sort: :colour}) end
  end

  test "last_created puts the newest entry first", ctx do
    for name <- ["Cora", "Ash", "Bram"], do: npc(ctx, name)

    assert ["Bram", "Ash", "Cora"] = names(ctx.gm, ctx.campaign, %{sort: :last_created})
  end

  test "last_edited puts the entry changed last first, and a text edit counts", ctx do
    cora = npc(ctx, "Cora")
    ash = npc(ctx, "Ash")
    npc(ctx, "Bram")

    assert ["Bram", "Ash", "Cora"] = names(ctx.gm, ctx.campaign, %{sort: :last_edited})

    Ash.update!(cora, %{name: "Cora II"}, action: :rename, actor: ctx.gm)
    assert ["Cora II", "Bram", "Ash"] = names(ctx.gm, ctx.campaign, %{sort: :last_edited})

    save_section!(Entry, ash.id, :description, [paragraph("A baker")], ctx.gm)
    assert ["Ash", "Cora II", "Bram"] = names(ctx.gm, ctx.campaign, %{sort: :last_edited})
  end

  test "saving the secret notes is no edit, so a player cannot tell when the GM wrote them",
       ctx do
    ash = npc(ctx, "Ash", %{shown: true})
    npc(ctx, "Bram", %{shown: true})
    before = Ash.get!(Entry, ash.id, actor: ctx.gm).edited_at

    save_section!(Entry, ash.id, :secret_notes, [paragraph("serves the lich")], ctx.gm)

    assert Ash.get!(Entry, ash.id, actor: ctx.gm).edited_at == before
    assert ["Bram", "Ash"] = names(ctx.player, ctx.campaign, %{sort: :last_edited})
    assert ["Bram", "Ash"] = names(ctx.gm, ctx.campaign, %{sort: :last_edited})
  end

  test "a rename, a hidden flag, an archive, a restore and a description each move edited_at",
       ctx do
    ash = npc(ctx, "Ash", %{shown: true})
    edited = fn -> Ash.get!(Entry, ash.id, actor: ctx.gm).edited_at end

    steps = [
      fn -> Ash.update!(ash, %{name: "Ash II"}, action: :rename, actor: ctx.gm) end,
      fn -> Ash.update!(ash, %{hidden: true}, action: :set_hidden, actor: ctx.gm) end,
      fn -> Ash.update!(ash, %{}, action: :archive, actor: ctx.gm) end,
      fn -> Ash.update!(ash, %{}, action: :restore, actor: ctx.gm) end,
      fn -> save_section!(Entry, ash.id, :description, [paragraph("A baker")], ctx.gm) end
    ]

    Enum.reduce(steps, edited.(), fn step, previous ->
      step.()
      now = edited.()
      assert DateTime.compare(now, previous) == :gt
      now
    end)
  end

  describe "last_mentioned" do
    setup ctx do
      s1 = session!(ctx)
      s2 = session!(ctx)
      s3 = session!(ctx)
      s4 = session!(ctx)

      early = npc(ctx, "Early", %{shown: true})
      late = npc(ctx, "Late", %{shown: true})
      by_player = npc(ctx, "By player", %{shown: true})
      prep_only = npc(ctx, "Prep only", %{shown: true})
      never = npc(ctx, "Never", %{shown: true})
      secret = npc(ctx, "Secret")

      save_section!(Session, s1.id, :log, mentioning(early), ctx.gm)
      save_section!(Session, s3.id, :log, mentioning([late, secret]), ctx.gm)
      save_section!(Session, s4.id, :prep, mentioning(prep_only), ctx.gm)

      log = Ash.create!(PlayerLog, %{session_id: s2.id}, actor: ctx.player)
      save_section!(PlayerLog, log.id, :body, mentioning(by_player), ctx.player)

      {:ok, never: never}
    end

    test "the entry in the latest session log comes first", ctx do
      # Late and Secret share session 3, so the name breaks the tie.
      assert ["Late", "Secret", "By player", "Early", "Never", "Prep only"] =
               names(ctx.gm, ctx.campaign, %{sort: :last_mentioned})
    end

    test "a player log counts, and prep never does", ctx do
      order = names(ctx.gm, ctx.campaign, %{sort: :last_mentioned})

      assert Enum.find_index(order, &(&1 == "By player")) <
               Enum.find_index(order, &(&1 == "Early"))

      # Prep only is mentioned in session 4 prep only, so it ranks with the unmentioned entries.
      assert ["Never", "Prep only"] = Enum.take(order, -2)
    end

    test "a player sees the same order without hidden entries or prep", ctx do
      gm_order = names(ctx.gm, ctx.campaign, %{sort: :last_mentioned})
      player_order = names(ctx.player, ctx.campaign, %{sort: :last_mentioned})

      refute "Secret" in player_order
      assert player_order == gm_order -- ["Secret"]
      assert ["Late", "By player", "Early", "Never", "Prep only"] = player_order
    end

    test "an archived list sorts the same way", ctx do
      for name <- ["Early", "Late"] do
        entry = Enum.find(list_all(ctx), &(&1.name == name))
        Ash.update!(entry, %{}, action: :archive, actor: ctx.gm)
      end

      assert ["Late", "Early"] =
               names(ctx.gm, ctx.campaign, %{sort: :last_mentioned, archived: true})
    end

    test "a mention in another campaign does not count", ctx do
      other = campaign(ctx.gm, "Other")
      other_session = Ash.create!(Session, %{campaign_id: other.id}, actor: ctx.gm)
      other_session2 = Ash.create!(Session, %{campaign_id: other.id}, actor: ctx.gm)
      assert other_session.number == 1 and other_session2.number == 2

      never = ctx.never
      save_section!(Session, other_session2.id, :log, mentioning(never), ctx.gm)

      order = names(ctx.gm, ctx.campaign, %{sort: :last_mentioned})
      assert ["Never", "Prep only"] = Enum.take(order, -2)
    end

    test "a campaign with no sessions sorts by name", ctx do
      other = campaign(ctx.gm, "Quiet")
      for name <- ["Zed", "Abe"], do: entry(ctx.gm, other, :npc, name)

      assert ["Abe", "Zed"] = names(ctx.gm, other, %{sort: :last_mentioned})
    end
  end

  test "a player never gets a hidden or archived-and-hidden entry with any sort", ctx do
    npc(ctx, "Shown", %{shown: true})
    npc(ctx, "Hidden")
    old = npc(ctx, "Old hidden")
    Ash.update!(old, %{}, action: :archive, actor: ctx.gm)

    for sort <- [:name, :last_edited, :last_created, :last_mentioned],
        archived <- [false, true] do
      assert names(ctx.player, ctx.campaign, %{sort: sort, archived: archived}) ==
               if(archived, do: [], else: ["Shown"])
    end
  end
end
