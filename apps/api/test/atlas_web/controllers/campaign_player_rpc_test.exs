defmodule AtlasWeb.CampaignPlayerRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    player = register(conn, "player@example.com")
    stranger = register(conn, "stranger@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    {:ok, gm: gm, player: player, stranger: stranger, campaign_id: campaign_id, conn: conn}
  end

  defp invite(ctx) do
    rpc(ctx.gm, "create_invitation", %{
      input: %{campaignId: ctx.campaign_id},
      fields: ["id", "token"]
    })
  end

  defp join(who, token),
    do: rpc(who, "join_campaign", %{input: %{token: token}, fields: ["id", "campaignId"]})

  defp get_campaign(who, id, fields \\ ["id", "name", "isGm", "gmName"]),
    do: rpc(who, "get_campaign", %{getBy: %{id: id}, fields: fields})

  defp not_found?(%{"success" => false, "errors" => [%{"type" => type} | _]}),
    do: type in ["not_found", "forbidden"]

  defp not_found?(_), do: false

  test "the GM creates one active invitation and can read it again", ctx do
    assert %{"success" => true, "data" => %{"token" => token}} = invite(ctx)

    assert %{"success" => true, "data" => %{"token" => ^token}} =
             rpc(ctx.gm, "get_active_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["token"]
             })

    assert %{"success" => false} = invite(ctx)
  end

  test "a player joins with the link, reads the campaign, and cannot change it", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)

    assert not_found?(get_campaign(ctx.player, ctx.campaign_id))

    assert %{"success" => true, "data" => %{"campaignId" => campaign_id}} =
             join(ctx.player, token)

    assert campaign_id == ctx.campaign_id

    assert %{"success" => true, "data" => %{"isGm" => false, "gmName" => "Test User"}} =
             get_campaign(ctx.player, ctx.campaign_id)

    assert %{"success" => true, "data" => [%{"id" => ^campaign_id}]} =
             rpc(ctx.player, "list_campaigns", %{fields: ["id", "isGm"]})

    assert %{"success" => true, "data" => %{"isGm" => true}} =
             get_campaign(ctx.gm, ctx.campaign_id)

    save = fn email ->
      Atlas.Fixtures.save_section(
        Atlas.Campaigns.Campaign,
        ctx.campaign_id,
        :description,
        [paragraph("hi")],
        email
      )
    end

    assert {:error, %Ash.Error.Forbidden{}} = save.("player@example.com")
    assert {:ok, _} = save.("gm@example.com")

    assert %{"success" => true, "data" => [_]} =
             rpc(ctx.player, "list_campaign_players", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id", "displayName"]
             })
  end

  test "joining twice keeps one membership", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true, "data" => %{"id" => id}} = join(ctx.player, token)
    assert %{"success" => true, "data" => %{"id" => ^id}} = join(ctx.player, token)

    assert %{"data" => [_only_one]} =
             rpc(ctx.gm, "list_campaign_players", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })
  end

  test "the GM cannot join their own campaign", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => false} = join(ctx.gm, token)
  end

  test "a revoked link stops new joins but keeps players, and the GM can issue a new link", ctx do
    assert %{"data" => %{"id" => id, "token" => token}} = invite(ctx)
    assert %{"success" => true} = join(ctx.player, token)

    assert %{"success" => true} =
             rpc(ctx.gm, "revoke_invitation", %{identity: id, input: %{}, fields: ["id"]})

    assert %{"success" => false} = join(ctx.stranger, token)
    assert not_found?(get_campaign(ctx.stranger, ctx.campaign_id))
    assert %{"success" => true} = get_campaign(ctx.player, ctx.campaign_id)

    assert %{"success" => true, "data" => nil} =
             rpc(ctx.gm, "get_active_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["token"]
             })

    assert %{"success" => true, "data" => %{"token" => new_token}} = invite(ctx)
    assert new_token != token
    assert %{"success" => true} = join(ctx.stranger, new_token)
  end

  test "an unknown token fails the same way as a revoked one", ctx do
    assert %{"success" => false, "errors" => [%{"message" => message} | _]} =
             join(ctx.player, "nope")

    assert message =~ "no longer valid"
  end

  test "only the GM can create, revoke, or read the link", ctx do
    assert %{"data" => %{"id" => id, "token" => token}} = invite(ctx)
    assert %{"success" => true} = join(ctx.player, token)

    for who <- [ctx.player, ctx.stranger] do
      refute rpc(who, "create_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })["success"]

      refute rpc(who, "revoke_invitation", %{identity: id, input: %{}, fields: ["id"]})["success"]

      assert %{"success" => true, "data" => nil} =
               rpc(who, "get_active_invitation", %{
                 input: %{campaignId: ctx.campaign_id},
                 fields: ["token"]
               })
    end
  end

  test "a link holder sees the campaign name and GM before joining", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)

    assert %{
             "success" => true,
             "data" => %{"campaignName" => "The Sunken Keep", "gmName" => "Test User"}
           } =
             rpc(ctx.stranger, "get_invitation_by_token", %{
               input: %{token: token},
               fields: ["campaignId", "campaignName", "gmName"]
             })

    assert %{"success" => true, "data" => nil} =
             rpc(ctx.stranger, "get_invitation_by_token", %{
               input: %{token: "nope"},
               fields: ["campaignId"]
             })
  end

  test "a player cannot read a hidden GM note, and non-members cannot list players", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true} = join(ctx.player, token)

    assert %{"success" => true, "data" => %{"id" => note_id}} =
             rpc(ctx.gm, "create_note", %{
               input: %{campaignId: ctx.campaign_id, title: "Secret plot"},
               fields: ["id"]
             })

    assert %{"success" => true, "data" => []} =
             rpc(ctx.player, "list_notes", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })

    assert not_found?(rpc(ctx.player, "get_note", %{getBy: %{id: note_id}, fields: ["id"]}))

    refute rpc(ctx.stranger, "create_note", %{
             input: %{campaignId: ctx.campaign_id, title: "Mine"},
             fields: ["id"]
           })["success"]

    assert %{"success" => true, "data" => []} =
             rpc(ctx.stranger, "list_campaign_players", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })
  end
end
