defmodule AtlasWeb.EntryRpcTest do
  @moduledoc """
  The app's view of world entries, and the check that MCP shows the same.

  The app calls the RPC actions below. MCP calls the tools. Both must show the same entries, the
  same names, hidden flags and texts, and hide the same things. An entry is text: neither surface
  has a status, fields, relations or a parent to show.
  """
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.McpHelpers, only: [token_for: 1, ok!: 3, call: 3]
  import AtlasWeb.RpcHelpers

  @fields [
    "id",
    "kind",
    "name",
    "hidden",
    "campaignId",
    "archivedAt",
    "isGm",
    "descriptionJson",
    "descriptionRevision",
    "secretNotesJson",
    "secretNotesRevision"
  ]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    outsider = register(conn, "outsider@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    assert %{"success" => true, "data" => %{"token" => token}} =
             rpc(gm, "create_invitation", %{input: %{campaignId: campaign_id}, fields: ["token"]})

    player = register(conn, "ann@example.com")

    assert %{"success" => true} =
             rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    {:ok,
     gm: gm,
     player: player,
     outsider: outsider,
     campaign_id: campaign_id,
     gm_token: token_for(Atlas.Fixtures.user_by_email("gm@example.com")),
     player_token: token_for(Atlas.Fixtures.user_by_email("ann@example.com"))}
  end

  defp create(ctx, kind, name) do
    assert %{"success" => true, "data" => data} =
             rpc(ctx.gm, "create_entry", %{
               input: %{campaignId: ctx.campaign_id, kind: kind, name: name},
               fields: @fields
             })

    data
  end

  defp act(who, action, id, input \\ %{}),
    do: rpc(who, action, %{identity: id, input: input, fields: @fields})

  defp list(who, ctx, input \\ %{}) do
    rpc(who, "list_entries", %{
      input: Map.merge(%{campaignId: ctx.campaign_id}, input),
      fields: @fields
    })["data"]
  end

  defp fetch(who, id), do: rpc(who, "get_entry", %{getBy: %{id: id}, fields: @fields})

  defp show(ctx, id, hidden \\ false),
    do: assert(%{"success" => true} = act(ctx.gm, "set_entry_hidden", id, %{hidden: hidden}))

  test "the GM creates an entry that starts hidden, and works with it", ctx do
    assert %{"id" => id, "kind" => "npc", "hidden" => true, "isGm" => true} =
             create(ctx, "npc", "Vex")

    assert %{"success" => true, "data" => %{"name" => "Vex"}} = fetch(ctx.gm, id)

    assert %{"success" => true, "data" => %{"name" => "Vexa"}} =
             act(ctx.gm, "rename_entry", id, %{name: "Vexa"})

    assert %{"success" => true, "data" => %{"archivedAt" => at}} =
             act(ctx.gm, "archive_entry", id)

    assert at
    assert [] = list(ctx.gm, ctx)
    assert [%{"id" => ^id}] = list(ctx.gm, ctx, %{archived: true})

    assert %{"success" => true, "data" => %{"archivedAt" => nil}} =
             act(ctx.gm, "restore_entry", id)

    assert [%{"id" => ^id}] = list(ctx.gm, ctx, %{kind: "npc"})
    assert [] = list(ctx.gm, ctx, %{kind: "location"})
  end

  test "an entry refuses metadata: its text carries every detail", ctx do
    for input <- [
          %{status: "dead"},
          %{fields: %{ancestry: "Elf"}},
          %{parentId: Ash.UUID.generate()},
          %{imageId: Ash.UUID.generate()}
        ] do
      assert %{"success" => false} =
               rpc(ctx.gm, "create_entry", %{
                 input: Map.merge(%{campaignId: ctx.campaign_id, kind: "npc", name: "V"}, input),
                 fields: ["id"]
               })
    end
  end

  test "a player cannot write, a non-member reads nothing", ctx do
    %{"id" => id} = create(ctx, "npc", "Vex")
    show(ctx, id)

    for {action, input} <- [
          {"rename_entry", %{name: "Mine"}},
          {"set_entry_hidden", %{hidden: true}},
          {"archive_entry", %{}},
          {"restore_entry", %{}}
        ] do
      assert %{"success" => false} = act(ctx.player, action, id, input), action
    end

    assert %{"success" => false} =
             rpc(ctx.player, "create_entry", %{
               input: %{campaignId: ctx.campaign_id, kind: "npc", name: "Mine"},
               fields: ["id"]
             })

    assert %{"success" => false} = fetch(ctx.outsider, id)
    assert [] = list(ctx.outsider, ctx)
    assert %{"data" => %{"name" => "Vex"}} = fetch(ctx.gm, id)
  end

  describe "the app and MCP match" do
    setup ctx do
      realm = create(ctx, "location", "Realm")
      show(ctx, realm["id"])

      keep = create(ctx, "location", "Keep")
      show(ctx, keep["id"])

      vex = create(ctx, "npc", "Vex")
      show(ctx, vex["id"])
      spy = create(ctx, "npc", "Spy")
      guild = create(ctx, "faction", "Guild")
      show(ctx, guild["id"])
      heist = create(ctx, "plot", "The heist")
      old = create(ctx, "item", "Old blade")
      show(ctx, old["id"])
      act(ctx.gm, "archive_entry", old["id"])

      for {entry, section, text} <- [
            {vex, :description, "Vex bakes bread for the guild"},
            {vex, :secret_notes, "Vex serves the lich"},
            {spy, :description, "The spy hides"}
          ] do
        Atlas.Fixtures.save_section!(
          Atlas.Content.Entry,
          entry["id"],
          section,
          [Atlas.Fixtures.paragraph(text)],
          Atlas.Fixtures.user_by_email("gm@example.com")
        )
      end

      {:ok, entries: [realm, keep, vex, spy, guild, heist, old]}
    end

    for who <- [:gm, :player] do
      test "list and get show the same to the #{who}", ctx do
        {app, token} = viewer(ctx, unquote(who))

        app_list = list(app, ctx)
        mcp_list = ok!(token, "list_entries", %{input: %{campaign_id: ctx.campaign_id}})

        assert Enum.sort(Enum.map(app_list, & &1["id"])) ==
                 Enum.sort(Enum.map(mcp_list, & &1["id"]))

        for entry <- app_list do
          mcp = Enum.find(mcp_list, &(&1["id"] == entry["id"]))

          assert {entry["kind"], entry["name"], entry["hidden"]} ==
                   {mcp["kind"], mcp["name"], mcp["hidden"]}
        end

        # An archived entry and a hidden one are in neither list for a player.
        names = Enum.map(app_list, & &1["name"])
        refute "Old blade" in names
        if unquote(who) == :player, do: refute("Spy" in names), else: assert("Spy" in names)

        for %{"id" => id} = entry <- app_list do
          %{"data" => app_entry} = fetch(app, id)
          mcp = ok!(token, "get_entry", %{input: %{id: id}})

          assert app_entry["descriptionRevision"] == mcp["description_revision"]
          assert app_entry["secretNotesRevision"] == mcp["secret_notes_revision"]
          assert is_nil(app_entry["secretNotesJson"]) == is_nil(mcp["secret_notes"])
          assert entry["name"] == mcp["name"]

          assert text(app_entry["descriptionJson"]) == text(mcp["description"])
        end
      end

      test "a player and the GM see the secret notes alike through the app and MCP (#{who})",
           ctx do
        {app, token} = viewer(ctx, unquote(who))
        vex = Enum.find(list(ctx.gm, ctx), &(&1["name"] == "Vex"))

        %{"data" => app_entry} = fetch(app, vex["id"])
        mcp = ok!(token, "get_entry", %{input: %{id: vex["id"]}})

        if unquote(who) == :gm do
          assert text(app_entry["secretNotesJson"]) == "Vex serves the lich"
          assert text(mcp["secret_notes"]) == "Vex serves the lich"
        else
          assert is_nil(app_entry["secretNotesJson"])
          assert is_nil(mcp["secret_notes"])
        end
      end

      test "search shows the same hits to the #{who}", ctx do
        {app, token} = viewer(ctx, unquote(who))

        for query <- ["vex", "lich", "spy", "guild", "heist", "blade"] do
          app_hits =
            rpc(app, "search", %{input: %{query: query}})["data"]["hits"]
            |> Enum.map(&{&1["kind"], &1["id"]})

          mcp_hits =
            ok!(token, "search", %{input: %{query: query}})["hits"]
            |> Enum.map(&{&1["kind"], &1["id"]})

          assert app_hits == mcp_hits, query
        end

        # The hidden spy and the GM-only notes never reach a player.
        player_hits = fn query ->
          rpc(app, "search", %{input: %{query: query}})["data"]["hits"]
        end

        if unquote(who) == :player do
          assert [] = player_hits.("spy")
          assert [] = player_hits.("lich")
          assert [] = player_hits.("blade")
          assert [%{"kind" => "npc"}] = player_hits.("vex")
        else
          assert [_] = player_hits.("spy")
          assert [_] = player_hits.("lich")
        end
      end
    end

    test "a mention shows the same label in the app list and through MCP", ctx do
      [_, _, _, spy | _] = ctx.entries
      vex = Enum.at(ctx.entries, 2)

      note =
        Ash.create!(
          Atlas.Content.Note,
          %{campaign_id: ctx.campaign_id, title: "Plan", visibility: :everyone},
          actor: Atlas.Fixtures.user_by_email("gm@example.com")
        )

      mention = fn entry ->
        %{"type" => "mention", "props" => %{"kind" => entry["kind"], "id" => entry["id"]}}
      end

      Atlas.Fixtures.save_section!(
        Atlas.Content.Note,
        note.id,
        :body,
        [%{Atlas.Fixtures.paragraph("") | "content" => [mention.(vex), mention.(spy)]}],
        Atlas.Fixtures.user_by_email("gm@example.com")
      )

      for who <- [:gm, :player] do
        {app, token} = viewer(ctx, who)
        readable = app |> list(ctx) |> Map.new(&{&1["id"], &1["name"]})
        app_labels = Enum.map([vex, spy], &Map.get(readable, &1["id"], "Restricted entry"))

        %{"body" => [%{"content" => content}]} = ok!(token, "get_note", %{input: %{id: note.id}})
        assert Enum.map(content, & &1["props"]["label"]) == app_labels
      end
    end

    test "the app and MCP refuse the same metadata", ctx do
      vex = Enum.at(ctx.entries, 2)

      for {key, value} <- [{"status", "dead"}, {"fields", %{"type" => "x"}}] do
        input = Map.put(%{campaignId: ctx.campaign_id, kind: "npc", name: "V"}, key, value)

        assert %{"success" => false} =
                 rpc(ctx.gm, "create_entry", %{input: input, fields: ["id"]})

        mcp_input = Map.put(%{campaign_id: ctx.campaign_id, kind: "npc", name: "V"}, key, value)

        assert {true, _} = call(ctx.gm_token, "create_entry", %{input: mcp_input})
      end

      # The old update tool is gone, so no client can invent fields.
      refute "update_entry" in Enum.map(tools(ctx.gm_token), & &1["name"])
      assert %{"success" => false} = act(ctx.gm, "update_entry", vex["id"], %{})
    end
  end

  defp viewer(ctx, :gm), do: {ctx.gm, ctx.gm_token}
  defp viewer(ctx, :player), do: {ctx.player, ctx.player_token}

  defp text(nil), do: nil

  defp text(blocks) do
    blocks
    |> Atlas.RichText.PlainText.render()
  end

  defp tools(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list"})
    |> json_response(200)
    |> get_in(["result", "tools"])
  end
end
