defmodule Atlas.Content.EntrySurfacesTest do
  @moduledoc "How world entries show in search, mentions and live editing."
  use Atlas.DataCase, async: false

  import Atlas.Fixtures

  alias Atlas.Campaigns.Campaign
  alias Atlas.Content.Entry
  alias Atlas.RichText.{Collab, Mentions}

  setup do
    gm = user()
    campaign = campaign(gm)
    {player, _character} = join_player(campaign, gm)
    {:ok, gm: gm, campaign: campaign, player: player}
  end

  defp search(actor, query, extra \\ %{}) do
    Atlas.Search.Request
    |> Ash.ActionInput.for_action(:search, Map.merge(%{query: query}, extra), actor: actor)
    |> Ash.run_action!()
  end

  defp hits(actor, query, extra \\ %{}),
    do: for(hit <- search(actor, query, extra).hits, do: {hit.kind, hit.title})

  defp mention(kind, id), do: %{"type" => "mention", "props" => %{"kind" => kind, "id" => id}}

  defp say(content) do
    %{
      "id" => "p1",
      "type" => "paragraph",
      "props" => %{},
      "content" => content,
      "children" => []
    }
  end

  defp show(entry, hidden, ctx),
    do: Ash.update!(entry, %{hidden: hidden}, action: :set_hidden, actor: ctx.gm)

  describe "search" do
    test "a hidden entry never matches for a player, by name or by text", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vexgard")
      save_section!(Entry, vex.id, :description, [paragraph("a baker of moonbread")], ctx.gm)

      assert [{:npc, "Vexgard"}] = hits(ctx.gm, "vexgard")
      assert [{:npc, "Vexgard"}] = hits(ctx.gm, "moonbread")
      assert [] = hits(ctx.player, "vexgard")
      assert [] = hits(ctx.player, "moonbread")
      assert search(ctx.player, "moonbread").more == false
    end

    test "showing an entry makes its name and description searchable by players", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vexgard")
      save_section!(Entry, vex.id, :description, [paragraph("a baker of moonbread")], ctx.gm)

      show(vex, false, ctx)
      assert [{:npc, "Vexgard"}] = hits(ctx.player, "vexgard")
      assert [{:npc, "Vexgard"}] = hits(ctx.player, "moonbread")

      [hit] = search(ctx.player, "moonbread").hits
      assert hit.campaign_id == ctx.campaign.id
      assert [%{section: :description}] = hit.sections

      show(vex, true, ctx)
      assert [] = hits(ctx.player, "vexgard")
      assert [] = hits(ctx.player, "moonbread")
    end

    test "secret notes never affect matches for a player, and the GM finds them", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vexgard", %{shown: true})
      save_section!(Entry, vex.id, :secret_notes, [paragraph("serves the vampirelord")], ctx.gm)

      assert [{:npc, "Vexgard"}] = hits(ctx.gm, "vampirelord")
      assert [] = hits(ctx.player, "vampirelord")

      [hit] = search(ctx.gm, "vampirelord").hits
      assert [%{section: :secret_notes}] = hit.sections
    end

    test "the kinds filter works for entries, and archived entries are still found", ctx do
      entry(ctx.gm, ctx.campaign, :npc, "Ashford")
      entry(ctx.gm, ctx.campaign, :location, "Ashford Keep")
      old = entry(ctx.gm, ctx.campaign, :item, "Ashford blade")

      assert [{:npc, _}] = hits(ctx.gm, "ashford", %{kinds: [:npc]})
      assert 3 == length(hits(ctx.gm, "ashford"))

      Ash.update!(old, %{}, action: :archive, actor: ctx.gm)
      assert 3 == length(hits(ctx.gm, "ashford"))
      assert [%{archived: true}] = Enum.filter(search(ctx.gm, "ashford").hits, & &1.archived)
    end

    test "a player finds an archived shown entry, and never an archived hidden one", ctx do
      shown = entry(ctx.gm, ctx.campaign, :item, "Zephyr blade", %{shown: true})
      hidden = entry(ctx.gm, ctx.campaign, :item, "Zephyr secret")
      for old <- [shown, hidden], do: Ash.update!(old, %{}, action: :archive, actor: ctx.gm)

      assert [{:item, "Zephyr blade"}] = hits(ctx.player, "zephyr")
      assert [%{archived: true}] = search(ctx.player, "zephyr").hits
      assert 2 == length(hits(ctx.gm, "zephyr"))
    end

    test "the archived filter keeps active and archived entries apart", ctx do
      entry(ctx.gm, ctx.campaign, :npc, "Wren active", %{shown: true})
      old = entry(ctx.gm, ctx.campaign, :npc, "Wren archived", %{shown: true})
      Ash.update!(old, %{}, action: :archive, actor: ctx.gm)

      kinds = Atlas.Content.EntrySpec.kinds()

      assert [{:npc, "Wren active"}] =
               hits(ctx.gm, "wren", %{kinds: kinds, archived: false})

      assert [{:npc, "Wren archived"}] =
               hits(ctx.gm, "wren", %{kinds: kinds, archived: true})

      assert 2 == length(hits(ctx.gm, "wren", %{kinds: kinds}))
    end

    test "the archived filter never shows a player a hidden entry", ctx do
      entry(ctx.gm, ctx.campaign, :npc, "Quill active")
      hidden = entry(ctx.gm, ctx.campaign, :npc, "Quill archived")
      shown = entry(ctx.gm, ctx.campaign, :npc, "Quill kept", %{shown: true})
      for old <- [hidden, shown], do: Ash.update!(old, %{}, action: :archive, actor: ctx.gm)

      for archived <- [nil, false, true] do
        extra = if archived == nil, do: %{}, else: %{archived: archived}
        titles = for {_, title} <- hits(ctx.player, "quill", extra), do: title
        refute "Quill active" in titles
        refute "Quill archived" in titles
      end

      assert [{:npc, "Quill kept"}] = hits(ctx.player, "quill", %{archived: true})
      assert [] = hits(ctx.player, "quill", %{archived: false})
    end

    test "offset reads the next page of the ranked hits, and more says when it ends", ctx do
      for n <- 1..5, do: entry(ctx.gm, ctx.campaign, :npc, "Pilot #{n}", %{shown: true})

      page = fn offset -> search(ctx.gm, "pilot", %{limit: 2, offset: offset}) end
      all = for hit <- search(ctx.gm, "pilot", %{limit: 5}).hits, do: hit.id

      assert %{more: true, hits: first} = page.(0)
      assert %{more: true, hits: second} = page.(2)
      assert %{more: false, hits: third} = page.(4)
      assert all == Enum.map(first ++ second ++ third, & &1.id)

      assert %{more: false, hits: []} = page.(6)
    end

    test "offset never reveals a hidden entry to a player", ctx do
      for n <- 1..3, do: entry(ctx.gm, ctx.campaign, :npc, "Lark #{n}")
      entry(ctx.gm, ctx.campaign, :npc, "Lark shown", %{shown: true})

      assert %{more: false, hits: [%{title: "Lark shown"}]} =
               search(ctx.player, "lark", %{limit: 1})

      assert %{more: false, hits: []} = search(ctx.player, "lark", %{limit: 1, offset: 1})
      assert %{more: true} = search(ctx.gm, "lark", %{limit: 1, offset: 2})
    end

    test "the title ranks before text, and entries rank with other kinds", ctx do
      entry(ctx.gm, ctx.campaign, :npc, "Mirelda", %{shown: true})

      note =
        Ash.create!(Atlas.Content.Note, %{campaign_id: ctx.campaign.id, title: "Intro"},
          actor: ctx.gm
        )

      save_section!(Atlas.Content.Note, note.id, :body, [paragraph("Mirelda waits")], ctx.gm)

      assert [{:npc, "Mirelda"}, {:note, "Intro"}] = hits(ctx.gm, "mirelda")
    end

    test "a mention of a hidden entry matches only for readers of that entry", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vexgard")

      save_section!(
        Campaign,
        ctx.campaign.id,
        :description,
        [say([mention("npc", vex.id)])],
        ctx.gm
      )

      assert [{:campaign, _}] = hits(ctx.gm, "vexgard") -- [{:npc, "Vexgard"}]
      assert [] = hits(ctx.player, "vexgard")

      show(vex, false, ctx)
      assert [{:npc, "Vexgard"}, {:campaign, _}] = hits(ctx.player, "vexgard")
    end
  end

  describe "mentions" do
    test "an entry that the reader may read has its name, and others are restricted", ctx do
      hidden = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      shown = entry(ctx.gm, ctx.campaign, :location, "Keep", %{shown: true})
      other = campaign(ctx.gm, "Other")
      elsewhere = entry(ctx.gm, other, :faction, "Elsewhere", %{shown: true})

      doc = [
        say([
          mention("npc", hidden.id),
          mention("location", shown.id),
          mention("faction", elsewhere.id),
          mention("creature", Ash.UUID.generate())
        ])
      ]

      gm_labels = Mentions.labels([doc], ctx.gm, ctx.campaign.id)
      assert gm_labels[{"npc", hidden.id}] == "Vex"
      assert gm_labels[{"location", shown.id}] == "Keep"
      refute Map.has_key?(gm_labels, {"faction", elsewhere.id})

      player_labels = Mentions.labels([doc], ctx.player, ctx.campaign.id)
      refute Map.has_key?(player_labels, {"npc", hidden.id})
      assert player_labels[{"location", shown.id}] == "Keep"
    end

    test "an archived entry keeps its name, and a hidden one stays restricted for a player",
         ctx do
      old = entry(ctx.gm, ctx.campaign, :item, "Old sword", %{shown: true})
      Ash.update!(old, %{}, action: :archive, actor: ctx.gm)
      secret = entry(ctx.gm, ctx.campaign, :item, "Old secret")
      Ash.update!(secret, %{}, action: :archive, actor: ctx.gm)
      doc = [say([mention("item", old.id), mention("item", secret.id)])]

      assert %{{"item", old.id} => "Old sword", {"item", secret.id} => "Old secret"} ==
               Mentions.labels([doc], ctx.gm, ctx.campaign.id)

      assert %{{"item", old.id} => "Old sword"} ==
               Mentions.labels([doc], ctx.player, ctx.campaign.id)
    end

    test "a mention names the kind of its entry, not just its ID", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      doc = [say([mention("location", vex.id)])]
      assert %{} == Mentions.labels([doc], ctx.gm, ctx.campaign.id)
    end

    test "a document accepts the six kinds of entry and refuses an unknown one", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vex")

      for kind <- ~w(npc location faction item creature plot) do
        assert {:ok, _} =
                 save_section(
                   Campaign,
                   ctx.campaign.id,
                   :description,
                   [say([mention(kind, vex.id)])],
                   ctx.gm
                 )
      end

      assert {:error, _} =
               save_section(
                 Campaign,
                 ctx.campaign.id,
                 :description,
                 [say([mention("spaceship", vex.id)])],
                 ctx.gm
               )
    end
  end

  describe "live editing" do
    test "the GM edits an entry's sections, and a player cannot write any", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vex", %{shown: true})

      for section <- [:description, :secret_notes] do
        {:ok, target} = Collab.parse("npc:#{vex.id}:#{section}")
        assert {:ok, %{can_write?: true}} = Collab.authorize(target, ctx.gm)
      end

      {:ok, description} = Collab.parse("npc:#{vex.id}:description")
      assert {:ok, %{can_write?: false}} = Collab.authorize(description, ctx.player)

      {:ok, secret} = Collab.parse("npc:#{vex.id}:secret_notes")
      assert {:error, :forbidden} = Collab.authorize(secret, ctx.player)
    end

    test "a hidden entry is closed to a player, and shown again opens it", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      {:ok, target} = Collab.parse("npc:#{vex.id}:description")

      assert {:error, :forbidden} = Collab.authorize(target, ctx.player)
      show(vex, false, ctx)
      assert {:ok, %{can_write?: false}} = Collab.authorize(target, ctx.player)
    end

    test "an entry opens only under its own kind", ctx do
      vex = entry(ctx.gm, ctx.campaign, :npc, "Vex")
      {:ok, wrong} = Collab.parse("location:#{vex.id}:description")
      assert {:error, :forbidden} = Collab.authorize(wrong, ctx.gm)
    end

    test "a section that the kind does not have is refused" do
      assert :error = Collab.parse("npc:#{Ash.UUID.generate()}:body")
      assert :error = Collab.parse("spaceship:#{Ash.UUID.generate()}:description")
    end
  end
end
