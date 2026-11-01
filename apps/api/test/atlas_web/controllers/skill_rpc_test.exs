defmodule AtlasWeb.SkillRpcTest do
  @moduledoc """
  The app's view of skills, and the check that MCP shows the same.

  A skill is global: it belongs to an account, not to a campaign. Only its owner reads or writes
  it, and only an account that is the GM of a campaign creates one. The app calls the RPC
  actions below. MCP calls the tools. Both must show the same skills and hide the same things.
  """
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.McpHelpers, only: [token_for: 1, ok!: 3, call: 3]
  import AtlasWeb.RpcHelpers

  alias Atlas.Fixtures
  alias Atlas.RichText.PlainText

  @fields ["id", "name", "description", "archivedAt", "bodyJson", "bodyRevision"]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    other_gm = register(conn, "other-gm@example.com")
    player = register(conn, "ann@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    assert %{"success" => true} =
             rpc(other_gm, "create_campaign", %{input: %{name: "Other Keep"}, fields: ["id"]})

    assert %{"success" => true, "data" => %{"token" => invite}} =
             rpc(gm, "create_invitation", %{input: %{campaignId: campaign_id}, fields: ["token"]})

    assert %{"success" => true} =
             rpc(player, "join_campaign", %{input: %{token: invite}, fields: ["id"]})

    {:ok,
     conn: conn,
     gm: gm,
     other_gm: other_gm,
     player: player,
     gm_user: Fixtures.user_by_email("gm@example.com"),
     other_user: Fixtures.user_by_email("other-gm@example.com"),
     player_user: Fixtures.user_by_email("ann@example.com")}
  end

  defp create(who, name, description \\ "") do
    rpc(who, "create_skill", %{
      input: %{name: name, description: description},
      fields: @fields
    })
  end

  defp list(who, archived \\ false),
    do: rpc(who, "list_skills", %{input: %{archived: archived}, fields: @fields})["data"]

  defp text(json), do: PlainText.render(json)

  defp initialize(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: "2025-06-18",
        capabilities: %{},
        clientInfo: %{name: "test", version: "1"}
      }
    })
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp tools(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{jsonrpc: "2.0", id: 2, method: "tools/list", params: %{}})
    |> json_response(200)
    |> get_in(["result", "tools"])
    |> Map.new(&{&1["name"], &1})
  end

  describe "who may use skills" do
    test "a GM creates a skill with an empty body", ctx do
      assert %{"success" => true, "data" => skill} =
               create(ctx.gm, "Session recap", "Use when the GM asks for a recap.")

      assert %{"name" => "Session recap", "bodyJson" => [], "archivedAt" => nil} = skill
      assert skill["description"] == "Use when the GM asks for a recap."
    end

    test "an account that runs no campaign cannot create a skill", ctx do
      assert %{"success" => false} = create(ctx.player, "Sneaky")
      assert list(ctx.player) == []
    end

    test "only the owner reads, changes or archives a skill, even another GM", ctx do
      %{"data" => %{"id" => id}} = create(ctx.gm, "Private")

      assert [%{"id" => ^id}] = list(ctx.gm)
      assert list(ctx.other_gm) == []
      assert list(ctx.player) == []

      for who <- [ctx.other_gm, ctx.player] do
        assert %{"success" => false} = rpc(who, "get_skill", %{getBy: %{id: id}, fields: ["id"]})

        for action <- ["update_skill", "archive_skill", "restore_skill"] do
          assert %{"success" => false} =
                   rpc(who, action, %{identity: id, input: %{}, fields: ["id"]})
        end
      end

      assert [%{"name" => "Private"}] = list(ctx.gm)
    end

    test "a skill is archived, never deleted, and a list can show either", ctx do
      %{"data" => %{"id" => id}} = create(ctx.gm, "Old rule")

      assert %{"success" => true} =
               rpc(ctx.gm, "archive_skill", %{identity: id, fields: ["id", "archivedAt"]})

      assert list(ctx.gm) == []
      assert [%{"id" => ^id}] = list(ctx.gm, true)

      assert %{"success" => true, "data" => %{"archivedAt" => nil}} =
               rpc(ctx.gm, "restore_skill", %{identity: id, fields: ["id", "archivedAt"]})

      assert [%{"id" => ^id}] = list(ctx.gm)
    end
  end

  describe "the app and MCP match" do
    setup ctx do
      %{"data" => recap} = create(ctx.gm, "Session recap", "Use for a recap.")
      %{"data" => voice} = create(ctx.gm, "NPC voice", "Use when you speak as an NPC.")
      %{"data" => old} = create(ctx.gm, "Old rule", "Not used any more.")
      rpc(ctx.gm, "archive_skill", %{identity: old["id"], fields: ["id"]})

      Fixtures.save_section!(
        Atlas.Content.Skill,
        recap["id"],
        :body,
        [Fixtures.paragraph("List what happened, then the open threads.")],
        ctx.gm_user
      )

      {:ok, recap: recap, voice: voice, token: token_for(ctx.gm_user)}
    end

    test "list and get show the same names, descriptions and text", ctx do
      app = list(ctx.gm)
      mcp = ok!(ctx.token, "list_skills", %{input: %{}})

      assert Enum.sort(Enum.map(app, & &1["id"])) == Enum.sort(Enum.map(mcp, & &1["id"]))
      refute "Old rule" in Enum.map(mcp, & &1["name"])

      for skill <- app do
        found = Enum.find(mcp, &(&1["id"] == skill["id"]))
        assert {skill["name"], skill["description"]} == {found["name"], found["description"]}

        %{"data" => detail} =
          rpc(ctx.gm, "get_skill", %{getBy: %{id: skill["id"]}, fields: @fields})

        read = ok!(ctx.token, "get_skill", %{input: %{id: skill["id"]}})

        assert detail["bodyRevision"] == read["body_revision"]
        assert detail["name"] == read["name"]

        # The app edits blocks. An agent reads the same text as Markdown.
        assert is_binary(read["body"])
        assert read["body"] == Atlas.RichText.Markdown.render(detail["bodyJson"])
        assert text(detail["bodyJson"]) == read["body"]
      end
    end

    test "get_skill returns Markdown that an agent follows, with no block JSON", ctx do
      assert %{"body" => body} = ok!(ctx.token, "get_skill", %{input: %{id: ctx.recap["id"]}})
      assert body == "List what happened, then the open threads."

      ok!(ctx.token, "edit_blocks", %{
        input: %{
          kind: "skill",
          id: ctx.recap["id"],
          section: "body",
          operations: [
            %{
              op: "insert",
              blocks: [
                %{type: "heading", props: %{level: 2}, content: "Rules"},
                %{type: "bulletListItem", content: "Be brief."}
              ]
            }
          ]
        }
      })

      assert %{"body" => body} = ok!(ctx.token, "get_skill", %{input: %{id: ctx.recap["id"]}})
      assert body == "List what happened, then the open threads.\n\n## Rules\n\n- Be brief."
      refute body =~ ~s("type")

      # read_blocks still gives the blocks and their ids for an edit.
      assert %{"blocks" => [%{"id" => _, "type" => "paragraph"} | _]} =
               ok!(ctx.token, "read_blocks", %{
                 input: %{kind: "skill", id: ctx.recap["id"], section: "body"}
               })
    end

    test "MCP lists archived skills on request, as the app does", ctx do
      assert ["Old rule"] ==
               ctx.token
               |> ok!("list_skills", %{input: %{archived: true}})
               |> Enum.map(& &1["name"])

      assert ["Old rule"] == Enum.map(list(ctx.gm, true), & &1["name"])
    end

    test "another account sees nothing through MCP, as in the app", ctx do
      for user <- [ctx.other_user, ctx.player_user] do
        token = token_for(user)
        assert ok!(token, "list_skills", %{input: %{}}) == []
        assert {true, _} = call(token, "get_skill", %{input: %{id: ctx.recap["id"]}})

        assert {true, _} =
                 call(token, "update_skill", %{id: ctx.recap["id"], input: %{name: "Mine now"}})

        assert {true, _} =
                 call(token, "edit_blocks", %{
                   input: %{
                     kind: "skill",
                     id: ctx.recap["id"],
                     section: "body",
                     operations: [%{op: "insert", blocks: [%{type: "paragraph", content: "x"}]}]
                   }
                 })
      end

      assert [%{"name" => "NPC voice"}, %{"name" => "Session recap"}] = list(ctx.gm)
    end

    test "an agent writes the body with edit_blocks and the app reads it", ctx do
      assert %{"saved" => true, "revision" => revision} =
               ok!(ctx.token, "edit_blocks", %{
                 input: %{
                   kind: "skill",
                   id: ctx.voice["id"],
                   section: "body",
                   operations: [
                     %{op: "insert", blocks: [%{type: "paragraph", content: "Growl, slowly."}]}
                   ]
                 }
               })

      assert %{"data" => detail} =
               rpc(ctx.gm, "get_skill", %{getBy: %{id: ctx.voice["id"]}, fields: @fields})

      assert text(detail["bodyJson"]) == "Growl, slowly."
      assert detail["bodyRevision"] == revision
    end

    test "only a GM is offered the tools that create or change skills", ctx do
      gm_tools = Map.keys(tools(ctx.token))
      player_tools = Map.keys(tools(token_for(ctx.player_user)))

      assert "create_skill" in gm_tools
      refute "create_skill" in player_tools
    end
  end

  describe "search" do
    setup ctx do
      %{"data" => recap} = create(ctx.gm, "Session recap", "Use for a recap.")
      %{"data" => old} = create(ctx.gm, "Retired zeppelin rule", "")
      rpc(ctx.gm, "archive_skill", %{identity: old["id"], fields: ["id"]})

      Fixtures.save_section!(
        Atlas.Content.Skill,
        recap["id"],
        :body,
        [Fixtures.paragraph("Always mention the cliffhanger first.")],
        ctx.gm_user
      )

      {:ok, recap: recap, token: token_for(ctx.gm_user)}
    end

    defp app_hits(who, input), do: rpc(who, "search", %{input: input})["data"]["hits"]

    test "the app and MCP find a skill by its name and by its text, alike", ctx do
      for query <- ["recap", "cliffhanger"] do
        app = app_hits(ctx.gm, %{query: query})
        mcp = ok!(ctx.token, "search", %{input: %{query: query}})["hits"]

        assert [%{"kind" => "skill", "id" => id, "campaign_id" => nil}] = app
        assert id == ctx.recap["id"]

        assert Enum.map(app, &{&1["kind"], &1["id"], &1["title"]}) ==
                 Enum.map(mcp, &{&1["kind"], &1["id"], &1["title"]})
      end

      assert [%{"sections" => [%{"section" => "body"}]}] =
               app_hits(ctx.gm, %{query: "cliffhanger"})
    end

    test "a campaign filter still finds the global skill", ctx do
      %{"data" => [%{"id" => campaign_id} | _]} =
        rpc(ctx.gm, "list_campaigns", %{fields: ["id"]})

      assert [%{"kind" => "skill"}] =
               app_hits(ctx.gm, %{query: "recap", campaignId: campaign_id})
    end

    test "nobody else finds a skill, and an archived skill is not found", ctx do
      for who <- [ctx.other_gm, ctx.player] do
        assert app_hits(who, %{query: "recap"}) == []
        assert app_hits(who, %{query: "cliffhanger"}) == []
      end

      for user <- [ctx.other_user, ctx.player_user] do
        assert ok!(token_for(user), "search", %{input: %{query: "recap"}})["hits"] == []
      end

      assert app_hits(ctx.gm, %{query: "zeppelin"}) == []
    end

    test "the kinds filter can ask for skills only", ctx do
      assert [%{"kind" => "skill"}] = app_hits(ctx.gm, %{query: "recap", kinds: ["skill"]})
      assert app_hits(ctx.gm, %{query: "recap", kinds: ["note"]}) == []
    end
  end

  describe "a skill has no mentions" do
    setup ctx do
      %{"data" => skill} = create(ctx.gm, "Voices")

      character =
        Ash.read!(Atlas.Campaigns.Character, authorize?: false) |> List.first()

      {:ok, skill: skill, token: token_for(ctx.gm_user), character: character}
    end

    test "edit_blocks refuses a mention in the body", ctx do
      mention = %{type: "mention", props: %{kind: "character", id: ctx.character.id}}

      assert {true, message} =
               call(ctx.token, "edit_blocks", %{
                 input: %{
                   kind: "skill",
                   id: ctx.skill["id"],
                   section: "body",
                   operations: [
                     %{op: "insert", blocks: [%{type: "paragraph", content: [mention]}]}
                   ]
                 }
               })

      assert message =~ "mention"

      assert %{"data" => %{"bodyJson" => []}} =
               rpc(ctx.gm, "get_skill", %{getBy: %{id: ctx.skill["id"]}, fields: ["bodyJson"]})
    end

    test "plain text and links are fine", ctx do
      assert %{"saved" => true} =
               ok!(ctx.token, "edit_blocks", %{
                 input: %{
                   kind: "skill",
                   id: ctx.skill["id"],
                   section: "body",
                   operations: [
                     %{
                       op: "insert",
                       blocks: [
                         %{
                           type: "paragraph",
                           content: [
                             %{type: "text", text: "See "},
                             %{
                               type: "link",
                               href: "https://2e.aonprd.com",
                               content: [%{type: "text", text: "AoN"}]
                             }
                           ]
                         }
                       ]
                     }
                   ]
                 }
               })
    end
  end

  describe "agents find skills without being told" do
    test "the server instructions begin with the order to call list_skills", ctx do
      %{"instructions" => instructions} = initialize(token_for(ctx.gm_user))

      first_line = instructions |> String.split("\n", parts: 2) |> hd()
      assert first_line =~ "call list_skills"
    end

    test "the tools that an agent calls first repeat the order", ctx do
      tools = tools(token_for(ctx.gm_user))

      for name <- ["list_campaigns", "get_campaign"] do
        assert tools[name]["description"] =~ "list_skills", "#{name} does not name list_skills"
      end

      assert tools["list_skills"]["description"] =~ "ALWAYS call this first"
    end
  end
end
