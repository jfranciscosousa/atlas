defmodule AtlasWeb.McpEntriesTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.McpHelpers

  alias Atlas.Fixtures

  setup do
    gm = Fixtures.user()
    campaign = Fixtures.campaign(gm)
    {player, _character} = Fixtures.join_player(campaign, gm)

    {:ok,
     gm: gm,
     campaign: campaign,
     player: player,
     token: token_for(gm),
     player_token: token_for(player)}
  end

  defp create(ctx, kind, name, extra \\ %{}) do
    ok!(
      ctx.token,
      "create_entry",
      %{input: Map.merge(%{campaign_id: ctx.campaign.id, kind: kind, name: name}, extra)}
    )
  end

  defp read(token, id), do: ok!(token, "get_entry", %{input: %{id: id}})

  defp list(token, ctx, extra \\ %{}),
    do: ok!(token, "list_entries", %{input: Map.merge(%{campaign_id: ctx.campaign.id}, extra)})

  defp show(ctx, id, hidden \\ false),
    do: ok!(ctx.token, "set_entry_hidden", %{id: id, input: %{hidden: hidden}})

  defp paragraph(text), do: %{type: "paragraph", content: text}

  test "the GM creates an entry of every kind, and it starts hidden", ctx do
    for kind <- ~w(npc location faction item creature plot) do
      assert %{"id" => id, "kind" => ^kind, "hidden" => true} = create(ctx, kind, "A #{kind}")
      assert %{"name" => "A " <> ^kind} = read(ctx.token, id)
    end

    assert 6 == length(list(ctx.token, ctx))
  end

  test "an entry is text: create and update refuse metadata", ctx do
    for extra <- [
          %{status: "dead"},
          %{fields: %{ancestry: "Elf"}},
          %{parent_id: Ash.UUID.generate()},
          %{image_id: Ash.UUID.generate()},
          %{custom_values: %{}}
        ] do
      assert {true, _} =
               call(ctx.token, "create_entry", %{
                 input: Map.merge(%{campaign_id: ctx.campaign.id, kind: "npc", name: "V"}, extra)
               })
    end

    %{"id" => id} = create(ctx, "npc", "Vex")

    for input <- [%{status: "dead"}, %{fields: %{ancestry: "Elf"}}] do
      assert {true, _} = call(ctx.token, "rename_entry", %{id: id, input: input})
    end

    # The metadata tool is gone, so no client can invent fields.
    refute "update_entry" in tool_names(ctx.token)
    assert %{"name" => "Vex"} = read(ctx.token, id)
  end

  test "rename, hide, show, archive and restore; nothing is deleted", ctx do
    %{"id" => id} = create(ctx, "item", "Sword")

    assert %{"name" => "Blade"} =
             ok!(ctx.token, "rename_entry", %{id: id, input: %{name: "Blade"}})

    assert %{"hidden" => false} = show(ctx, id)
    assert %{"hidden" => true} = show(ctx, id, true)

    assert %{"archived_at" => at} = ok!(ctx.token, "archive_entry", %{id: id})
    assert at
    assert [] = list(ctx.token, ctx)
    assert [%{"id" => ^id}] = list(ctx.token, ctx, %{archived: true})
    refute ok!(ctx.token, "restore_entry", %{id: id})["archived_at"]
    assert [%{"id" => ^id}] = list(ctx.token, ctx)

    refute Enum.any?(tool_names(ctx.token), &String.contains?(&1, "delete"))
    assert "archive_entry" in tool_names(ctx.token)
  end

  test "list_entries filters by kind", ctx do
    create(ctx, "location", "Realm")
    create(ctx, "location", "Keep")
    create(ctx, "npc", "Vex")

    assert ["Keep", "Realm"] =
             ctx.token |> list(ctx, %{kind: "location"}) |> Enum.map(& &1["name"]) |> Enum.sort()

    assert [%{"name" => "Vex", "kind" => "npc", "hidden" => true}] =
             list(ctx.token, ctx, %{kind: "npc"})
  end

  describe "players" do
    test "never see a hidden entry, and see a shown one without the secret notes", ctx do
      %{"id" => id} = create(ctx, "npc", "Vex")

      assert [] = list(ctx.player_token, ctx)
      assert {true, _} = call(ctx.player_token, "get_entry", %{input: %{id: id}})

      assert {true, _} =
               call(ctx.player_token, "read_blocks", %{
                 input: %{kind: "npc", id: id, section: "description"}
               })

      show(ctx, id)

      assert [%{"id" => ^id, "name" => "Vex", "hidden" => false}] = list(ctx.player_token, ctx)

      assert %{
               "name" => "Vex",
               "description" => [],
               "secret_notes" => nil,
               "secret_notes_revision" => nil
             } = read(ctx.player_token, id)

      assert {true, _} =
               call(ctx.player_token, "read_blocks", %{
                 input: %{kind: "npc", id: id, section: "secret_notes"}
               })

      show(ctx, id, true)
      assert [] = list(ctx.player_token, ctx)
      assert {true, _} = call(ctx.player_token, "get_entry", %{input: %{id: id}})
    end

    test "cannot create, change, show, archive or restore", ctx do
      %{"id" => id} = create(ctx, "npc", "Vex")
      show(ctx, id)

      assert {true, _} =
               call(ctx.player_token, "create_entry", %{
                 input: %{campaign_id: ctx.campaign.id, kind: "npc", name: "Mine"}
               })

      for {tool, args} <- [
            {"rename_entry", %{id: id, input: %{name: "Mine"}}},
            {"set_entry_hidden", %{id: id, input: %{hidden: true}}},
            {"archive_entry", %{id: id}},
            {"restore_entry", %{id: id}}
          ] do
        assert {true, _} = call(ctx.player_token, tool, args), tool
      end

      assert %{"name" => "Vex"} = read(ctx.token, id)
    end
  end

  describe "text" do
    test "edit_blocks and read_blocks take the entry kinds and both sections", ctx do
      for kind <- ~w(npc location faction item creature plot),
          section <- ~w(description secret_notes) do
        %{"id" => id} = create(ctx, kind, "A #{kind}")

        assert {false, saved} =
                 call(ctx.token, "edit_blocks", %{
                   input: %{
                     kind: kind,
                     id: id,
                     section: section,
                     operations: [%{op: "insert", blocks: [paragraph("Text of #{section}")]}]
                   }
                 })

        assert %{"saved" => true, "revision" => 1} = Jason.decode!(saved)

        assert %{"revision" => 1, "blocks" => [%{"content" => [%{"text" => "Text of " <> _}]}]} =
                 ok!(ctx.token, "read_blocks", %{input: %{kind: kind, id: id, section: section}})

        assert %{^section => [_], "description_revision" => _} = read(ctx.token, id)
      end
    end

    test "an entry opens only under its own kind", ctx do
      %{"id" => id} = create(ctx, "npc", "Vex")

      assert {true, _} =
               call(ctx.token, "read_blocks", %{
                 input: %{kind: "location", id: id, section: "description"}
               })
    end

    test "a player cannot edit a shown entry or read its secret notes", ctx do
      %{"id" => id} = create(ctx, "npc", "Vex")
      show(ctx, id)

      assert {true, _} =
               call(ctx.player_token, "edit_blocks", %{
                 input: %{
                   kind: "npc",
                   id: id,
                   section: "description",
                   operations: [%{op: "insert", blocks: [paragraph("x")]}]
                 }
               })

      assert %{"blocks" => []} =
               ok!(ctx.player_token, "read_blocks", %{
                 input: %{kind: "npc", id: id, section: "description"}
               })
    end

    test "a mention of an entry has the name that the reader may see", ctx do
      %{"id" => vex} = create(ctx, "npc", "Vex")
      %{"id" => keep} = create(ctx, "location", "Keep")
      show(ctx, keep)

      %{"id" => note} =
        ok!(ctx.token, "create_note", %{input: %{campaign_id: ctx.campaign.id, title: "Plan"}})

      ok!(ctx.token, "set_note_visibility", %{id: note, input: %{visibility: "everyone"}})

      mention = fn kind, id -> %{type: "mention", props: %{kind: kind, id: id}} end

      assert {false, _} =
               call(ctx.token, "edit_blocks", %{
                 input: %{
                   kind: "note",
                   id: note,
                   section: "body",
                   operations: [
                     %{
                       op: "insert",
                       blocks: [
                         %{
                           type: "paragraph",
                           content: [mention.("npc", vex), mention.("location", keep)]
                         }
                       ]
                     }
                   ]
                 }
               })

      labels = fn token ->
        %{"body" => [%{"content" => content}]} = ok!(token, "get_note", %{input: %{id: note}})
        Enum.map(content, & &1["props"]["label"])
      end

      assert ["Vex", "Keep"] = labels.(ctx.token)
      assert ["Restricted entry", "Keep"] = labels.(ctx.player_token)

      ok!(ctx.token, "archive_entry", %{id: keep})
      assert ["Vex", "Deleted entry"] = labels.(ctx.token)
      assert ["Restricted entry", "Restricted entry"] = labels.(ctx.player_token)
    end
  end

  describe "search" do
    test "finds entries by kind, and hides hidden ones from players", ctx do
      %{"id" => id} = create(ctx, "npc", "Vexgard")
      %{"id" => plot} = create(ctx, "plot", "Vexgard plot")
      show(ctx, plot)

      search = fn token, args ->
        ok!(token, "search", %{input: Map.merge(%{query: "vexgard"}, args)})["hits"]
      end

      assert [%{"kind" => "npc", "id" => ^id}, %{"kind" => "plot"}] = search.(ctx.token, %{})
      assert [%{"kind" => "plot"}] = search.(ctx.player_token, %{})
      assert [%{"kind" => "npc"}] = search.(ctx.token, %{kinds: ["npc"]})
      assert [] = search.(ctx.player_token, %{kinds: ["npc"]})
    end
  end

  test "the entry tools say what to write in the text", ctx do
    %{"description" => create} = tool(ctx.token, "create_entry")

    for text <- ~w(npc location faction item creature plot) do
      assert create =~ text
    end

    for hint <- ~w(person place organization object monster story) do
      assert create =~ hint
    end

    assert create =~ "label for grouping"
    assert create =~ "edit_blocks"
    assert create =~ "infer"

    %{"description" => read} = tool(ctx.token, "get_entry")
    assert read =~ "text"
    assert read =~ "secret notes"
    refute read =~ "status"

    assert %{"description" => edit} = tool(ctx.token, "edit_blocks")
    assert edit =~ "npc, location, faction, item, creature, plot (description, secret_notes)"
  end

  defp tool_names(token), do: token |> tools() |> Enum.map(& &1["name"])
  defp tool(token, name), do: token |> tools() |> Enum.find(&(&1["name"] == name))

  defp tools(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list"})
    |> json_response(200)
    |> get_in(["result", "tools"])
  end
end
