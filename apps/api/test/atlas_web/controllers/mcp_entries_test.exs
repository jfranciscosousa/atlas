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

  test "the GM creates an entry of every kind: hidden, with the default status", ctx do
    for {kind, status} <- [
          {"npc", "alive"},
          {"location", "active"},
          {"faction", "active"},
          {"item", "unknown"},
          {"creature", "active"},
          {"plot", "planned"}
        ] do
      assert %{"id" => id, "kind" => ^kind, "hidden" => true, "status" => ^status} =
               create(ctx, kind, "A #{kind}")

      assert %{"name" => "A " <> ^kind, "fields" => %{}, "relations" => []} = read(ctx.token, id)
    end

    assert 6 == length(list(ctx.token, ctx))
  end

  test "create takes status and fields, and update merges the fields", ctx do
    assert %{"id" => id, "status" => "dead", "fields" => %{"ancestry" => "Elf"}} =
             create(ctx, "npc", "Vex", %{status: "dead", fields: %{ancestry: "Elf"}})

    assert %{"fields" => %{"ancestry" => "Elf", "gender" => "Female"}} =
             ok!(ctx.token, "update_entry", %{
               id: id,
               input: %{fields: %{gender: "Female"}}
             })

    assert %{"fields" => %{"gender" => "Female"}} =
             ok!(ctx.token, "update_entry", %{id: id, input: %{fields: %{ancestry: ""}}})

    assert %{"status" => "missing"} =
             ok!(ctx.token, "update_entry", %{id: id, input: %{status: "missing"}})

    assert {true, _} = call(ctx.token, "update_entry", %{id: id, input: %{status: "planned"}})
    assert {true, _} = call(ctx.token, "update_entry", %{id: id, input: %{fields: %{type: "x"}}})
  end

  test "a location takes a parent, and only a location does", ctx do
    %{"id" => realm} = create(ctx, "location", "Realm")
    %{"id" => keep} = create(ctx, "location", "Keep", %{parent_id: realm})

    assert %{"parent_id" => ^realm, "parent_name" => "Realm"} = read(ctx.token, keep)

    assert {true, _} = call(ctx.token, "update_entry", %{id: realm, input: %{parent_id: keep}})

    # A tool result leaves out the attributes that are nil.
    refute ok!(ctx.token, "update_entry", %{id: keep, input: %{parent_id: nil}})["parent_id"]
    assert %{"parent_id" => nil} = read(ctx.token, keep)

    assert {true, _} =
             call(ctx.token, "create_entry", %{
               input: %{campaign_id: ctx.campaign.id, kind: "npc", name: "V", parent_id: realm}
             })
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

    tools = tool_names(ctx.token)
    refute Enum.any?(tools, &String.contains?(&1, "delete"))
    assert "archive_entry" in tools
  end

  test "list_entries filters by kind and shows the parent location", ctx do
    %{"id" => realm} = create(ctx, "location", "Realm")
    create(ctx, "location", "Keep", %{parent_id: realm})
    create(ctx, "npc", "Vex")

    assert ["Keep", "Realm"] =
             ctx.token |> list(ctx, %{kind: "location"}) |> Enum.map(& &1["name"]) |> Enum.sort()

    assert [%{"name" => "Keep", "parent_name" => "Realm"}] =
             ctx.token |> list(ctx, %{kind: "location"}) |> Enum.filter(&(&1["name"] == "Keep"))

    assert [%{"name" => "Vex", "kind" => "npc", "status" => "alive", "hidden" => true}] =
             list(ctx.token, ctx, %{kind: "npc"})
  end

  describe "players" do
    test "never see a hidden entry, and see a shown one without the secret notes", ctx do
      %{"id" => id} = create(ctx, "npc", "Vex", %{fields: %{ancestry: "Elf"}})

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
               "fields" => %{"ancestry" => "Elf"},
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

    test "cannot create, change, show, archive or relate", ctx do
      %{"id" => id} = create(ctx, "npc", "Vex")
      show(ctx, id)
      %{"id" => guild} = create(ctx, "faction", "Guild")
      show(ctx, guild)

      assert {true, _} =
               call(ctx.player_token, "create_entry", %{
                 input: %{campaign_id: ctx.campaign.id, kind: "npc", name: "Mine"}
               })

      for {tool, args} <- [
            {"rename_entry", %{id: id, input: %{name: "Mine"}}},
            {"update_entry", %{id: id, input: %{status: "dead"}}},
            {"set_entry_hidden", %{id: id, input: %{hidden: true}}},
            {"archive_entry", %{id: id}},
            {"restore_entry", %{id: id}}
          ] do
        assert {true, _} = call(ctx.player_token, tool, args), tool
      end

      assert {true, _} =
               call(ctx.player_token, "add_entry_relation", %{
                 input: %{
                   campaign_id: ctx.campaign.id,
                   from_kind: "npc",
                   from_id: id,
                   to_kind: "faction",
                   to_id: guild,
                   relation: "member_of"
                 }
               })

      assert %{"name" => "Vex", "status" => "alive"} = read(ctx.token, id)
    end
  end

  describe "relations" do
    defp relate(ctx, from, to, relation, extra \\ %{}) do
      ok!(ctx.token, "add_entry_relation", %{
        input:
          Map.merge(
            %{
              campaign_id: ctx.campaign.id,
              from_kind: from.kind,
              from_id: from.id,
              to_kind: to.kind,
              to_id: to.id,
              relation: relation
            },
            extra
          )
      })
    end

    test "add, read in both directions, and remove", ctx do
      %{"id" => vex} = create(ctx, "npc", "Vex")
      %{"id" => guild} = create(ctx, "faction", "Guild")

      relation =
        relate(ctx, %{kind: "npc", id: vex}, %{kind: "faction", id: guild}, "member_of", %{
          label: "staff"
        })

      assert %{"id" => relation_id, "relation" => "member_of", "label" => "staff"} = relation

      assert %{
               "relations" => [
                 %{
                   "id" => ^relation_id,
                   "direction" => "outgoing",
                   "text" => "member of",
                   "label" => "staff",
                   "other" => %{"kind" => "faction", "id" => ^guild, "name" => "Guild"}
                 }
               ]
             } = read(ctx.token, vex)

      assert %{
               "relations" => [
                 %{
                   "direction" => "incoming",
                   "text" => "members",
                   "other" => %{"kind" => "npc", "id" => ^vex, "name" => "Vex"}
                 }
               ]
             } = read(ctx.token, guild)

      assert {true, _} =
               call(ctx.token, "add_entry_relation", %{
                 input: %{
                   campaign_id: ctx.campaign.id,
                   from_kind: "faction",
                   from_id: guild,
                   to_kind: "npc",
                   to_id: vex,
                   relation: "member_of"
                 }
               })

      assert {false, _} = call(ctx.token, "remove_entry_relation", %{id: relation_id})
      assert %{"relations" => []} = read(ctx.token, vex)
      assert %{"name" => "Vex"} = read(ctx.token, vex)
    end

    test "a player sees a relation only when both ends are shown", ctx do
      %{"id" => vex} = create(ctx, "npc", "Vex")
      %{"id" => guild} = create(ctx, "faction", "Guild")
      show(ctx, guild)

      relate(ctx, %{kind: "npc", id: vex}, %{kind: "faction", id: guild}, "member_of")
      assert %{"relations" => []} = read(ctx.player_token, guild)

      show(ctx, vex)
      assert %{"relations" => [%{"other" => %{"name" => "Vex"}}]} = read(ctx.player_token, guild)

      assert {true, _} =
               call(ctx.player_token, "remove_entry_relation", %{id: Ash.UUID.generate()})
    end

    test "the tool description lists the relations and the kinds", ctx do
      %{"description" => description} = tool(ctx.token, "add_entry_relation")

      for relation <-
            ~w(member_of located_in headquarters_of held_by allied_with enemy_of involves) do
        assert description =~ relation
      end
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

      assert {true, _} =
               call(ctx.token, "edit_blocks", %{
                 input: %{
                   kind: "location",
                   id: id,
                   section: "description",
                   operations: [%{op: "insert", blocks: [paragraph("x")]}]
                 }
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

  test "the tool descriptions name the kinds, statuses and fields", ctx do
    %{"description" => create} = tool(ctx.token, "create_entry")

    for text <-
          ~w(npc location faction item creature plot alive disbanded planned reputation ancestry source) do
      assert create =~ text
    end

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
