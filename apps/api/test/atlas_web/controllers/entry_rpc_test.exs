defmodule AtlasWeb.EntryRpcTest do
  @moduledoc """
  The app's view of world entries, and the check that MCP shows the same.

  The app calls the RPC actions below. MCP calls the tools. Both must show the same entries, the
  same names, statuses, fields, relations and texts, and hide the same things.
  """
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.McpHelpers, only: [token_for: 1, ok!: 3, call: 3]
  import AtlasWeb.RpcHelpers

  @fields [
    "id",
    "kind",
    "name",
    "status",
    "hidden",
    "fields",
    "campaignId",
    "parentId",
    "parentName",
    "imageId",
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

  defp create(ctx, kind, name, extra \\ %{}) do
    assert %{"success" => true, "data" => data} =
             rpc(ctx.gm, "create_entry", %{
               input: Map.merge(%{campaignId: ctx.campaign_id, kind: kind, name: name}, extra),
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
    assert %{"id" => id, "kind" => "npc", "hidden" => true, "status" => "alive", "isGm" => true} =
             create(ctx, "npc", "Vex", %{fields: %{ancestry: "Elf"}})

    assert %{"success" => true, "data" => %{"fields" => %{"ancestry" => "Elf"}}} =
             fetch(ctx.gm, id)

    assert %{"success" => true, "data" => %{"name" => "Vexa"}} =
             act(ctx.gm, "rename_entry", id, %{name: "Vexa"})

    assert %{"success" => true, "data" => %{"status" => "dead", "fields" => fields}} =
             act(ctx.gm, "update_entry", id, %{status: "dead", fields: %{gender: "Female"}})

    assert fields == %{"ancestry" => "Elf", "gender" => "Female"}

    assert %{"success" => false} = act(ctx.gm, "update_entry", id, %{status: "planned"})
    assert %{"success" => false} = act(ctx.gm, "update_entry", id, %{fields: %{type: "x"}})

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

  test "the app can read the kinds with their statuses, fields and relations", ctx do
    assert %{"success" => true, "data" => %{"kinds" => kinds, "relations" => relations}} =
             rpc(ctx.gm, "get_entry_kinds", %{})

    assert Enum.map(kinds, & &1["kind"]) == ~w(npc location faction item creature plot)
    npc = Enum.find(kinds, &(&1["kind"] == "npc"))
    assert npc["statuses"] == ~w(alive dead missing unknown)
    assert Enum.map(npc["fields"], & &1["key"]) == ~w(ancestry gender)

    assert Enum.map(relations, & &1["relation"]) ==
             ~w(member_of located_in headquarters_of held_by allied_with enemy_of involves)
  end

  test "a player cannot write, a non-member reads nothing", ctx do
    %{"id" => id} = create(ctx, "npc", "Vex")
    show(ctx, id)

    for {action, input} <- [
          {"rename_entry", %{name: "Mine"}},
          {"update_entry", %{status: "dead"}},
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

  test "relations: add, list in both directions, remove, and visibility", ctx do
    %{"id" => vex} = create(ctx, "npc", "Vex")
    %{"id" => guild} = create(ctx, "faction", "Guild")
    show(ctx, guild)

    assert %{"success" => true, "data" => %{"id" => relation_id}} =
             rpc(ctx.gm, "create_entry_relation", %{
               input: %{
                 campaignId: ctx.campaign_id,
                 fromKind: "npc",
                 fromId: vex,
                 toKind: "faction",
                 toId: guild,
                 relation: "member_of",
                 label: "staff"
               },
               fields: ["id"]
             })

    relations = fn who, end_id ->
      rpc(who, "list_entry_relations", %{
        input: %{campaignId: ctx.campaign_id, endId: end_id},
        fields: [
          "id",
          "relation",
          "label",
          "fromKind",
          "fromId",
          "toKind",
          "toId",
          "fromName",
          "toName"
        ]
      })["data"]
    end

    assert [%{"relation" => "member_of", "fromName" => "Vex", "toName" => "Guild"}] =
             relations.(ctx.gm, vex)

    assert [%{"id" => ^relation_id}] = relations.(ctx.gm, guild)
    assert [] = relations.(ctx.player, guild)

    show(ctx, vex)
    assert [%{"label" => "staff"}] = relations.(ctx.player, guild)

    assert %{"success" => false} =
             rpc(ctx.player, "delete_entry_relation", %{identity: relation_id})

    assert %{"success" => true} = rpc(ctx.gm, "delete_entry_relation", %{identity: relation_id})
    assert [] = relations.(ctx.gm, vex)
  end

  describe "the app and MCP match" do
    setup ctx do
      realm = create(ctx, "location", "Realm", %{fields: %{type: "Kingdom"}})
      show(ctx, realm["id"])

      keep = create(ctx, "location", "Keep", %{parentId: realm["id"]})
      show(ctx, keep["id"])

      vex = create(ctx, "npc", "Vex", %{fields: %{ancestry: "Elf"}})
      show(ctx, vex["id"])
      spy = create(ctx, "npc", "Spy")
      guild = create(ctx, "faction", "Guild", %{fields: %{reputation: "Friendly"}})
      show(ctx, guild["id"])
      heist = create(ctx, "plot", "The heist", %{status: "active"})
      old = create(ctx, "item", "Old blade")
      show(ctx, old["id"])
      act(ctx.gm, "archive_entry", old["id"])

      for {from, to, kind, relation} <- [
            {vex, guild, "faction", "member_of"},
            {spy, guild, "faction", "member_of"},
            {vex, keep, "location", "located_in"},
            {heist, vex, "npc", "involves"}
          ] do
        assert %{"success" => true} =
                 rpc(ctx.gm, "create_entry_relation", %{
                   input: %{
                     campaignId: ctx.campaign_id,
                     fromKind: from["kind"],
                     fromId: from["id"],
                     toKind: kind,
                     toId: to["id"],
                     relation: relation
                   },
                   fields: ["id"]
                 })
      end

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

          assert {entry["kind"], entry["name"], entry["status"], entry["hidden"]} ==
                   {mcp["kind"], mcp["name"], mcp["status"], mcp["hidden"]}

          assert entry["parentName"] == mcp["parent_name"]
        end

        # An archived entry and a hidden one are in neither list for a player.
        names = Enum.map(app_list, & &1["name"])
        refute "Old blade" in names
        if unquote(who) == :player, do: refute("Spy" in names), else: assert("Spy" in names)

        for %{"id" => id} = entry <- app_list do
          %{"data" => app_entry} = fetch(app, id)
          mcp = ok!(token, "get_entry", %{input: %{id: id}})

          assert app_entry["fields"] == mcp["fields"]
          assert app_entry["parentId"] == mcp["parent_id"]
          assert app_entry["parentName"] == mcp["parent_name"]
          assert app_entry["imageId"] == mcp["image_id"]
          assert app_entry["descriptionRevision"] == mcp["description_revision"]
          assert app_entry["secretNotesRevision"] == mcp["secret_notes_revision"]
          assert is_nil(app_entry["secretNotesJson"]) == is_nil(mcp["secret_notes"])
          assert entry["name"] == mcp["name"]

          assert text(app_entry["descriptionJson"]) == text(mcp["description"])

          assert app_relations(app, ctx, id) == mcp_relations(mcp)
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

    test "the app and MCP refuse the same writes", ctx do
      vex = Enum.at(ctx.entries, 2)

      for {app_action, tool, input} <- [
            {"update_entry", "update_entry", %{status: "planned"}},
            {"update_entry", "update_entry", %{fields: %{type: "x"}}},
            {"update_entry", "update_entry", %{parentId: Enum.at(ctx.entries, 0)["id"]}}
          ] do
        mcp_input =
          for {key, value} <- input, into: %{}, do: {Macro.underscore(to_string(key)), value}

        assert %{"success" => false} = act(ctx.gm, app_action, vex["id"], input)
        assert {true, _} = call(ctx.gm_token, tool, %{id: vex["id"], input: mcp_input})
      end
    end
  end

  defp viewer(ctx, :gm), do: {ctx.gm, ctx.gm_token}
  defp viewer(ctx, :player), do: {ctx.player, ctx.player_token}

  defp text(nil), do: nil

  defp text(blocks) do
    blocks
    |> Atlas.RichText.PlainText.render()
  end

  defp app_relations(app, ctx, id) do
    rpc(app, "list_entry_relations", %{
      input: %{campaignId: ctx.campaign_id, endId: id},
      fields: [
        "id",
        "relation",
        "label",
        "fromKind",
        "fromId",
        "toKind",
        "toId",
        "fromName",
        "toName"
      ]
    })["data"]
    |> Enum.map(fn relation ->
      outgoing? = relation["fromId"] == id

      %{
        id: relation["id"],
        relation: relation["relation"],
        outgoing?: outgoing?,
        other:
          if(outgoing?,
            do: {relation["toKind"], relation["toId"], relation["toName"]},
            else: {relation["fromKind"], relation["fromId"], relation["fromName"]}
          )
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp mcp_relations(mcp) do
    mcp["relations"]
    |> Enum.map(fn relation ->
      %{
        id: relation["id"],
        relation: relation["relation"],
        outgoing?: relation["direction"] == "outgoing",
        other: {relation["other"]["kind"], relation["other"]["id"], relation["other"]["name"]}
      }
    end)
    |> Enum.sort_by(& &1.id)
  end
end
