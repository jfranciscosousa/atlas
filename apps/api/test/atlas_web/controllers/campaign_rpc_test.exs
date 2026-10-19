defmodule AtlasWeb.CampaignRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  @fields ["id", "name", "descriptionJson", "descriptionRevision", "progressRewardsRevision"]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    other = register(conn, "other@example.com")
    other_gm = register(conn, "other-gm@example.com")

    assert %{"success" => true} =
             rpc(other_gm, "create_campaign", %{input: %{name: "Elsewhere"}, fields: @fields})

    assert %{"success" => true, "data" => %{"id" => id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: @fields})

    {:ok, conn: conn, gm: gm, other: other, other_gm: other_gm, id: id}
  end

  defp save(who, id, expected, text \\ "hi", action \\ "save_campaign_description") do
    rpc(who, action, %{
      identity: id,
      input: %{json: [paragraph(text)], schemaVersion: 1, expectedRevision: expected},
      fields: @fields
    })
  end

  test "a signed-in user creates a campaign, becomes its GM, and sees two empty sections", ctx do
    assert %{
             "success" => true,
             "data" => %{
               "name" => "The Sunken Keep",
               "descriptionJson" => [],
               "descriptionRevision" => 0
             }
           } = rpc(ctx.gm, "get_campaign", %{getBy: %{id: ctx.id}, fields: @fields})

    assert %{"success" => true, "data" => [%{"id" => id}]} =
             rpc(ctx.gm, "list_campaigns", %{fields: @fields})

    assert id == ctx.id
  end

  test "the GM saves both sections independently", ctx do
    assert %{"success" => true, "data" => %{"descriptionRevision" => 1}} = save(ctx.gm, ctx.id, 0)

    assert %{"success" => true, "data" => %{"progressRewardsRevision" => 1}} =
             save(ctx.gm, ctx.id, 0, "loot", "save_campaign_progress_rewards")

    assert %{"success" => false, "errors" => [%{"type" => "stale_revision"} | _]} =
             save(ctx.gm, ctx.id, 0)
  end

  test "non-members and GMs of other campaigns cannot read or save: they get not found", ctx do
    for who <- [ctx.other, ctx.other_gm] do
      assert %{"success" => false, "errors" => [%{"type" => "not_found"} | _]} =
               rpc(who, "get_campaign", %{getBy: %{id: ctx.id}, fields: @fields})

      assert %{"success" => false, "errors" => [%{"type" => type} | _]} = save(who, ctx.id, 0)
      assert type == "not_found"

      assert %{"success" => true, "data" => data} = rpc(who, "list_campaigns", %{fields: @fields})
      refute ctx.id in Enum.map(data, & &1["id"])
    end

    assert %{"data" => %{"descriptionRevision" => 0}} =
             rpc(ctx.gm, "get_campaign", %{getBy: %{id: ctx.id}, fields: @fields})
  end

  test "anonymous requests are rejected", ctx do
    for {action, params} <- [
          {"list_campaigns", %{fields: @fields}},
          {"get_campaign", %{getBy: %{id: ctx.id}, fields: @fields}},
          {"create_campaign", %{input: %{name: "x"}, fields: @fields}}
        ] do
      assert %{"error" => "Sign in to continue."} = rpc(ctx.conn, action, params, 401)
    end
  end

  test "clients cannot set the GM, revision, or schema columns", ctx do
    other_id = json_response(ctx.other, 200)["user"]["id"]

    for input <- [%{name: "x", gmId: other_id}, %{name: "x", descriptionRevision: 9}] do
      assert %{"success" => false} =
               rpc(ctx.gm, "create_campaign", %{input: input, fields: @fields})
    end
  end

  test "names must be present and at most 200 characters", ctx do
    for input <- [%{}, %{name: "  "}, %{name: String.duplicate("a", 201)}] do
      assert %{"success" => false} =
               rpc(ctx.gm, "create_campaign", %{input: input, fields: @fields})
    end
  end

  test "the server rejects invalid documents and unsupported schema versions", ctx do
    bad_doc = [%{paragraph("x") | "type" => "video"}]

    assert %{"success" => false} =
             rpc(ctx.gm, "save_campaign_description", %{
               identity: ctx.id,
               input: %{json: bad_doc, schemaVersion: 1, expectedRevision: 0},
               fields: @fields
             })

    assert %{"success" => false} =
             rpc(ctx.gm, "save_campaign_description", %{
               identity: ctx.id,
               input: %{json: [paragraph("x")], schemaVersion: 2, expectedRevision: 0},
               fields: @fields
             })

    assert %{"data" => %{"descriptionRevision" => 0, "descriptionJson" => []}} =
             rpc(ctx.gm, "get_campaign", %{getBy: %{id: ctx.id}, fields: @fields})
  end
end
