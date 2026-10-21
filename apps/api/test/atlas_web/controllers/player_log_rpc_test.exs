defmodule AtlasWeb.PlayerLogRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  @fields ["id", "isMine", "authorName", "bodyJson", "bodyRevision"]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    ann = register(conn, "ann@example.com")
    bob = register(conn, "bob@example.com")
    outsider = register(conn, "out@example.com")

    assert %{"data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    assert %{"data" => %{"token" => token}} =
             rpc(gm, "create_invitation", %{input: %{campaignId: campaign_id}, fields: ["token"]})

    for player <- [ann, bob],
        do:
          assert(
            %{"success" => true} =
              rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})
          )

    assert %{"data" => %{"id" => session_id}} =
             rpc(gm, "create_session", %{input: %{campaignId: campaign_id}, fields: ["id"]})

    {:ok, gm: gm, ann: ann, bob: bob, outsider: outsider, session_id: session_id}
  end

  defp create(who, session_id),
    do: rpc(who, "create_player_log", %{input: %{sessionId: session_id}, fields: @fields})

  defp list(who, session_id),
    do: rpc(who, "list_player_logs", %{input: %{sessionId: session_id}, fields: @fields})

  defp save(email, id, doc, opts \\ []),
    do: Atlas.Fixtures.save_section(Atlas.Campaigns.PlayerLog, id, :body, doc, email, opts)

  test "a player writes a log; every member reads every player log", ctx do
    assert %{"success" => true, "data" => %{"id" => ann_log, "isMine" => true}} =
             create(ctx.ann, ctx.session_id)

    assert %{"success" => true, "data" => %{"id" => bob_log}} = create(ctx.bob, ctx.session_id)

    assert {:ok, %{body_revision: 1}} =
             save("ann@example.com", ann_log, [paragraph("Ann saw a ghost.")])

    for reader <- [ctx.gm, ctx.ann, ctx.bob] do
      assert %{"success" => true, "data" => [%{"id" => ^ann_log}, %{"id" => ^bob_log}] = logs} =
               list(reader, ctx.session_id)

      assert [%{"content" => [%{"text" => "Ann saw a ghost."}]}] =
               Enum.find(logs, &(&1["id"] == ann_log))["bodyJson"]
    end

    assert %{"data" => [%{"isMine" => false}, %{"isMine" => true}]} =
             list(ctx.bob, ctx.session_id)

    assert %{"data" => [%{"isMine" => false}, %{"isMine" => false}]} =
             list(ctx.gm, ctx.session_id)
  end

  test "starting a log twice returns the first one", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.session_id)
    assert %{"success" => true, "data" => %{"id" => ^id}} = create(ctx.ann, ctx.session_id)
    assert %{"data" => [_only_one]} = list(ctx.ann, ctx.session_id)
  end

  test "only the author writes a log, and a stale revision is rejected", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.session_id)

    for other <- ["bob@example.com", "gm@example.com", "out@example.com"],
        do: assert({:error, %Ash.Error.Forbidden{}} = save(other, id, [paragraph("Mine now.")]))

    assert {:ok, _} = save("ann@example.com", id, [paragraph("one")])

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{} | _]}} =
             save("ann@example.com", id, [paragraph("two")], revision: 0)
  end

  test "the GM and outsiders cannot start a log; outsiders read nothing", ctx do
    assert %{"success" => false} = create(ctx.gm, ctx.session_id)
    assert %{"success" => false} = create(ctx.outsider, ctx.session_id)
    assert %{"data" => %{"id" => _}} = create(ctx.ann, ctx.session_id)

    assert %{"success" => true, "data" => []} = list(ctx.outsider, ctx.session_id)
    assert %{"data" => [_]} = list(ctx.gm, ctx.session_id)
  end
end
