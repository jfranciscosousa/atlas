defmodule AtlasWeb.ClaimRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    player = register(conn, "player@example.com")
    member = register(conn, "member@example.com")
    stranger = register(conn, "stranger@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    {:ok,
     conn: conn,
     gm: gm,
     player: player,
     member: member,
     stranger: stranger,
     campaign_id: campaign_id}
  end

  defp prepare(ctx, label \\ "Ana") do
    rpc(ctx.gm, "create_unclaimed_character", %{
      input: %{campaignId: ctx.campaign_id, playerLabel: label},
      fields: ["id", "claimed", "playerName", "claimPath"]
    })
  end

  defp token_of(%{"claimPath" => "/claim/" <> token}), do: token

  defp claim(who, token),
    do: rpc(who, "claim_character", %{input: %{token: token}, fields: ["id", "campaignId"]})

  defp characters(who, ctx, fields \\ ["id", "playerName", "claimed", "isMine"]),
    do: rpc(who, "list_characters", %{input: %{campaignId: ctx.campaign_id}, fields: fields})

  test "the GM prepares a character; it is unclaimed and shows the label as the player", ctx do
    assert %{
             "success" => true,
             "data" => %{"claimed" => false, "playerName" => "Ana", "claimPath" => path}
           } = prepare(ctx)

    assert "/claim/" <> _ = path

    # The GM may not leave the label out.
    refute rpc(ctx.gm, "create_unclaimed_character", %{
             input: %{campaignId: ctx.campaign_id, playerLabel: ""},
             fields: ["id"]
           })["success"]
  end

  test "only the GM prepares a character", ctx do
    assert %{"data" => %{"token" => token}} =
             rpc(ctx.gm, "create_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["token"]
             })

    assert %{"success" => true} =
             rpc(ctx.player, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    for who <- [ctx.player, ctx.stranger] do
      refute prepare(%{ctx | gm: who})["success"]
    end
  end

  test "an unclaimed character makes nobody a member and is nobody's", ctx do
    assert %{"success" => true} = prepare(ctx)

    assert %{"success" => true, "data" => [%{"claimed" => false, "isMine" => false}]} =
             characters(ctx.gm, ctx)

    assert %{"success" => true, "data" => []} = characters(ctx.stranger, ctx)
  end

  test "the player claims with the link, becomes a member, and the link stops working", ctx do
    assert %{"data" => prepared} = prepare(ctx)
    token = token_of(prepared)

    assert %{"success" => true, "data" => %{"id" => id, "campaignId" => campaign_id}} =
             claim(ctx.player, token)

    assert id == prepared["id"]
    assert campaign_id == ctx.campaign_id

    assert %{"success" => true, "data" => [%{"claimed" => true, "isMine" => true}]} =
             characters(ctx.player, ctx)

    # Now the account's name replaces the label, and nobody gets the link any more.
    assert %{"data" => [%{"playerName" => "Test User"}]} = characters(ctx.gm, ctx)

    assert %{"data" => %{"claimPath" => nil}} =
             rpc(ctx.gm, "get_character", %{getBy: %{id: id}, fields: ["claimPath"]})

    assert %{"success" => false} = claim(ctx.member, token)
    assert %{"success" => false} = claim(ctx.player, token)
  end

  test "a member may claim another character, and claiming adds no character", ctx do
    assert %{"data" => first} = prepare(ctx, "Ana")
    assert %{"data" => second} = prepare(ctx, "Ana")

    assert %{"success" => true} = claim(ctx.player, token_of(first))
    assert %{"success" => true} = claim(ctx.player, token_of(second))

    assert %{"data" => [%{"isMine" => true}, %{"isMine" => true}]} = characters(ctx.player, ctx)
  end

  test "the GM cannot claim, and an unknown token fails like a used one", ctx do
    assert %{"data" => prepared} = prepare(ctx)

    assert %{"success" => false, "errors" => [%{"message" => message} | _]} =
             claim(ctx.gm, token_of(prepared))

    assert message =~ "GM"

    assert %{"success" => false, "errors" => [%{"message" => message} | _]} =
             claim(ctx.player, "nope")

    assert message =~ "no longer valid"
  end

  test "a player never reads the claim link of an unclaimed character", ctx do
    assert %{"data" => prepared} = prepare(ctx)

    assert %{"data" => %{"token" => token}} =
             rpc(ctx.gm, "create_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["token"]
             })

    assert %{"success" => true} =
             rpc(ctx.member, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    assert %{"success" => true, "data" => player_view} =
             rpc(ctx.member, "get_character", %{
               getBy: %{id: prepared["id"]},
               fields: ["claimPath", "claimed"]
             })

    assert player_view["claimPath"] == nil
    refute inspect(player_view) =~ token_of(prepared)
  end

  describe "GET /api/claims/:token" do
    test "shows who is invited without a session", ctx do
      assert %{"data" => prepared} = prepare(ctx, "Ana")

      assert %{
               "characterName" => nil,
               "playerLabel" => "Ana",
               "campaignName" => "The Sunken Keep",
               "gmName" => "Test User"
             } =
               build_conn()
               |> get("/api/claims/" <> token_of(prepared))
               |> json_response(200)
    end

    test "returns the same 404 for an unknown and a used token", ctx do
      assert %{"data" => prepared} = prepare(ctx)
      token = token_of(prepared)
      assert %{"success" => true} = claim(ctx.player, token)

      for t <- [token, "nope"] do
        assert %{"error" => _} = build_conn() |> get("/api/claims/" <> t) |> json_response(404)
      end
    end
  end
end
