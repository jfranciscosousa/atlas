defmodule AtlasWeb.SessionDraftLogRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    ann = register(conn, "ann@example.com")
    outsider = register(conn, "out@example.com")

    assert %{"data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    assert %{"data" => %{"token" => token}} =
             rpc(gm, "create_invitation", %{input: %{campaignId: campaign_id}, fields: ["token"]})

    assert %{"success" => true} =
             rpc(ann, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    assert %{"data" => %{"id" => session_id}} =
             rpc(gm, "create_session", %{input: %{campaignId: campaign_id}, fields: ["id"]})

    {:ok, gm: gm, ann: ann, outsider: outsider, session_id: session_id}
  end

  defp draft(who, session_id),
    do:
      rpc(who, "draft_session_log", %{
        input: %{id: session_id},
        fields: ["draft", "conflicts"]
      })

  test "the GM gets a draft built from the log and the player logs, never the prep", ctx do
    alias Atlas.Campaigns.{PlayerLog, Session}

    gm = Atlas.Fixtures.user_by_email("gm@example.com")
    Atlas.Fixtures.save_section!(Session, ctx.session_id, :log, [paragraph("GM saw a door.")], gm)

    Atlas.Fixtures.save_section!(
      Session,
      ctx.session_id,
      :prep,
      [paragraph("SECRET twist.")],
      gm
    )

    assert %{"data" => %{"id" => log_id}} =
             rpc(ctx.ann, "create_player_log", %{
               input: %{sessionId: ctx.session_id},
               fields: ["id"]
             })

    Atlas.Fixtures.save_section!(
      PlayerLog,
      log_id,
      :body,
      [paragraph("Ann opened it.")],
      "ann@example.com"
    )

    assert %{
             "success" => true,
             "data" => %{"draft" => "# Draft\n\nThe party won.", "conflicts" => []}
           } =
             draft(ctx.gm, ctx.session_id)

    assert_received {:llm_prompt, prompt}
    assert prompt =~ "GM saw a door."
    assert prompt =~ "Ann opened it."
    refute prompt =~ "SECRET"
  end

  test "a session without any log text is refused", ctx do
    assert %{"success" => false} = draft(ctx.gm, ctx.session_id)
    refute_received {:llm_prompt, _}
  end

  test "the GM gets the conflicts the model finds, apart from the draft", ctx do
    Atlas.Fixtures.save_section!(
      Atlas.Campaigns.Session,
      ctx.session_id,
      :log,
      [paragraph("CONFLICT")],
      Atlas.Fixtures.user_by_email("gm@example.com")
    )

    assert %{"data" => %{"draft" => draft, "conflicts" => ["Ann and the GM disagree."]}} =
             draft(ctx.gm, ctx.session_id)

    refute draft =~ "disagree"
  end

  test "a failing model call returns a readable error", ctx do
    Atlas.Fixtures.save_section!(
      Atlas.Campaigns.Session,
      ctx.session_id,
      :log,
      [paragraph("NO KEY")],
      Atlas.Fixtures.user_by_email("gm@example.com")
    )

    assert %{"success" => false, "errors" => [%{"message" => message}]} =
             draft(ctx.gm, ctx.session_id)

    assert message =~ "the AI is not available"
  end

  test "a player and an outsider cannot ask for a draft", ctx do
    Atlas.Fixtures.save_section!(
      Atlas.Campaigns.Session,
      ctx.session_id,
      :log,
      [paragraph("GM saw a door.")],
      Atlas.Fixtures.user_by_email("gm@example.com")
    )

    for who <- [ctx.ann, ctx.outsider] do
      assert %{"success" => false} = draft(who, ctx.session_id)
    end

    refute_received {:llm_prompt, _}
  end
end
