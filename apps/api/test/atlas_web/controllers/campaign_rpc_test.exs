defmodule AtlasWeb.CampaignRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1, save_section: 5, save_section: 6]

  alias Atlas.Campaigns.Campaign

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

  defp save(email, id, text \\ "hi", section \\ :description, opts \\ []),
    do: save_section(Campaign, id, section, [paragraph(text)], email, opts)

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
    assert {:ok, %{description_revision: 1}} = save("gm@example.com", ctx.id)

    assert {:ok, %{progress_rewards_revision: 1}} =
             save("gm@example.com", ctx.id, "loot", :progress_rewards)

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{} | _]}} =
             save("gm@example.com", ctx.id, "hi", :description, revision: 0)
  end

  test "non-members and GMs of other campaigns cannot read or save", ctx do
    for {who, email} <- [{ctx.other, "other@example.com"}, {ctx.other_gm, "other-gm@example.com"}] do
      assert %{"success" => false, "errors" => [%{"type" => "not_found"} | _]} =
               rpc(who, "get_campaign", %{getBy: %{id: ctx.id}, fields: @fields})

      assert {:error, %Ash.Error.Forbidden{}} = save(email, ctx.id)

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

    assert {:error, %Ash.Error.Invalid{}} =
             save_section(Campaign, ctx.id, :description, bad_doc, "gm@example.com")

    assert {:error, %Ash.Error.Invalid{}} =
             save_section(Campaign, ctx.id, :description, [paragraph("x")], "gm@example.com",
               schema_version: 2
             )

    assert %{"data" => %{"descriptionRevision" => 0, "descriptionJson" => []}} =
             rpc(ctx.gm, "get_campaign", %{getBy: %{id: ctx.id}, fields: @fields})
  end
end
