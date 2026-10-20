defmodule AtlasWeb.SessionRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  @fields [
    "id",
    "campaignId",
    "number",
    "title",
    "playedOn",
    "status",
    "logJson",
    "logRevision",
    "prepJson",
    "prepSchemaVersion",
    "prepRevision"
  ]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    other = register(conn, "other@example.com")
    player = register(conn, "ann@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    assert %{"success" => true, "data" => %{"token" => token}} =
             rpc(gm, "create_invitation", %{input: %{campaignId: campaign_id}, fields: ["token"]})

    assert %{"success" => true} =
             rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    {:ok, conn: conn, gm: gm, other: other, player: player, campaign_id: campaign_id}
  end

  defp create(who, campaign_id),
    do: rpc(who, "create_session", %{input: %{campaignId: campaign_id}, fields: @fields})

  defp save(who, action, id, expected, doc),
    do:
      rpc(who, action, %{
        identity: id,
        input: %{json: doc, schemaVersion: 1, expectedRevision: expected},
        fields: ["id", "logRevision"]
      })

  test "the GM creates numbered sessions, sets details, and writes prep and log", ctx do
    assert %{"success" => true, "data" => %{"id" => first, "number" => 1, "title" => nil}} =
             create(ctx.gm, ctx.campaign_id)

    assert %{"success" => true, "data" => %{"id" => second, "number" => 2}} =
             create(ctx.gm, ctx.campaign_id)

    assert %{
             "success" => true,
             "data" => %{"title" => "Into the Keep", "playedOn" => "2026-10-20"}
           } =
             rpc(ctx.gm, "update_session_details", %{
               identity: first,
               input: %{title: "Into the Keep", playedOn: "2026-10-20"},
               fields: @fields
             })

    assert %{"success" => true, "data" => %{"logRevision" => 1}} =
             save(ctx.gm, "save_session_log", first, 0, [paragraph("They arrived.")])

    assert %{"success" => true} =
             save(ctx.gm, "save_session_prep", first, 0, [paragraph("The abbot lies.")])

    assert %{"success" => true, "data" => [%{"id" => ^second}, %{"id" => ^first}]} =
             rpc(ctx.gm, "list_sessions", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })

    assert %{"success" => false, "errors" => [%{"type" => "stale_revision"} | _]} =
             save(ctx.gm, "save_session_log", first, 0, [paragraph("again")])
  end

  test "a session starts in prep; only the GM moves it to done and back", ctx do
    assert %{"data" => %{"id" => id, "status" => "in_prep"}} = create(ctx.gm, ctx.campaign_id)

    set = fn who, status ->
      rpc(who, "update_session_details", %{
        identity: id,
        input: %{status: status},
        fields: @fields
      })
    end

    assert %{"success" => true, "data" => %{"status" => "done"}} = set.(ctx.gm, "done")

    assert %{"success" => true, "data" => %{"status" => "done"}} =
             rpc(ctx.player, "get_session", %{getBy: %{id: id}, fields: @fields})

    assert %{"success" => false} = set.(ctx.player, "in_prep")
    assert %{"success" => false} = set.(ctx.gm, "played")
    assert %{"success" => true, "data" => %{"status" => "in_prep"}} = set.(ctx.gm, "in_prep")
  end

  test "numbering starts at 1 in each campaign", ctx do
    assert %{"data" => %{"id" => other_campaign}} =
             rpc(ctx.gm, "create_campaign", %{input: %{name: "Another"}, fields: ["id"]})

    assert %{"data" => %{"number" => 1}} = create(ctx.gm, ctx.campaign_id)
    assert %{"data" => %{"number" => 1}} = create(ctx.gm, other_campaign)
  end

  test "a player reads the session and its log but never receives the prep", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)
    assert %{"success" => true} = save(ctx.gm, "save_session_log", id, 0, [paragraph("Public.")])
    assert %{"success" => true} = save(ctx.gm, "save_session_prep", id, 0, [paragraph("Secret.")])

    assert %{"success" => true, "data" => session} =
             rpc(ctx.player, "get_session", %{getBy: %{id: id}, fields: @fields})

    assert [%{"content" => [%{"text" => "Public."}]}] = session["logJson"]
    assert session["prepJson"] == nil
    assert session["prepSchemaVersion"] == nil
    assert session["prepRevision"] == nil

    assert %{"success" => true, "data" => [listed]} =
             rpc(ctx.player, "list_sessions", %{
               input: %{campaignId: ctx.campaign_id},
               fields: @fields
             })

    assert listed["prepJson"] == nil

    refute inspect(rpc(ctx.player, "get_session", %{getBy: %{id: id}, fields: @fields})) =~
             "Secret."
  end

  test "a player sees a session whose log is empty", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    assert %{"success" => true, "data" => [%{"id" => ^id, "logJson" => []}]} =
             rpc(ctx.player, "list_sessions", %{
               input: %{campaignId: ctx.campaign_id},
               fields: @fields
             })
  end

  test "a player cannot create, edit details, save the log, or save the prep", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    assert %{"success" => false} = create(ctx.player, ctx.campaign_id)

    assert %{"success" => false} =
             rpc(ctx.player, "update_session_details", %{
               identity: id,
               input: %{title: "Mine"},
               fields: @fields
             })

    assert %{"success" => false} = save(ctx.player, "save_session_log", id, 0, [paragraph("x")])
    assert %{"success" => false} = save(ctx.player, "save_session_prep", id, 0, [paragraph("x")])

    assert %{"data" => %{"title" => nil, "logRevision" => 0, "prepRevision" => 0}} =
             rpc(ctx.gm, "get_session", %{getBy: %{id: id}, fields: @fields})

    assert %{"data" => [_only_one]} =
             rpc(ctx.gm, "list_sessions", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })
  end

  test "someone outside the campaign gets nothing: not found", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    assert %{"success" => false} = create(ctx.other, ctx.campaign_id)

    assert %{"success" => true, "data" => []} =
             rpc(ctx.other, "list_sessions", %{
               input: %{campaignId: ctx.campaign_id},
               fields: @fields
             })

    assert %{"success" => false, "errors" => [%{"type" => "not_found"} | _]} =
             rpc(ctx.other, "get_session", %{getBy: %{id: id}, fields: @fields})

    assert %{"success" => false} = save(ctx.other, "save_session_log", id, 0, [paragraph("x")])
  end

  test "sessions have no archive or delete action" do
    names = Atlas.Campaigns.Session |> Ash.Resource.Info.actions() |> Enum.map(& &1.type)
    refute :destroy in names
    refute Ash.Resource.Info.attribute(Atlas.Campaigns.Session, :archived_at)
  end
end
