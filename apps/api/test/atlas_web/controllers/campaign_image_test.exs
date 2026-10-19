defmodule AtlasWeb.CampaignImageTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.ImageFixtures
  import AtlasWeb.RpcHelpers

  @fields ["id", "descriptionRevision", "progressRewardsRevision"]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    other = register(conn, "other@example.com")
    other_gm = register(conn, "other-gm@example.com")

    %{"data" => %{"id" => campaign}} =
      rpc(gm, "create_campaign", %{input: %{name: "Keep"}, fields: @fields})

    %{"data" => %{"id" => elsewhere}} =
      rpc(other_gm, "create_campaign", %{input: %{name: "Elsewhere"}, fields: @fields})

    {:ok,
     conn: conn,
     gm: gm,
     other: other,
     other_gm: other_gm,
     campaign: campaign,
     elsewhere: elsewhere}
  end

  defp url(who, image_id, campaign, section) do
    rpc(who, "get_campaign_image_url", %{
      input: %{id: image_id, campaignId: campaign, section: section}
    })
  end

  defp image_block(id) do
    %{
      "id" => "img",
      "type" => "image",
      "props" => %{"url" => "atlas-image:#{id}"},
      "children" => []
    }
  end

  defp save(who, campaign, section, blocks, expected \\ 0) do
    rpc(who, "save_campaign_#{section}", %{
      identity: campaign,
      input: %{json: blocks, schemaVersion: 1, expectedRevision: expected},
      fields: @fields
    })
  end

  test "the GM uploads an image and loads it through a fresh signed URL", ctx do
    assert %{"id" => id, "width" => 64, "height" => 48, "animated" => false} =
             upload(ctx.gm, ctx.campaign, "description", png())

    assert %{"success" => true, "data" => "/api/images/" <> _ = signed} =
             url(ctx.gm, id, ctx.campaign, "description")

    response = get(build_conn(), signed)
    assert response.status == 200
    assert ["image/webp" <> _] = get_resp_header(response, "content-type")
    assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = response.resp_body
  end

  test "a GIF animation survives and an SVG is rasterized", ctx do
    assert %{"animated" => true, "width" => 64, "height" => 48} =
             upload(ctx.gm, ctx.campaign, "description", animated(".gif"))

    assert %{"animated" => false, "width" => 120, "height" => 80} =
             upload(ctx.gm, ctx.campaign, "description", svg())
  end

  test "the server rejects wrong types, oversize files and too many pixels", ctx do
    assert %{"error" => _} = upload(ctx.gm, ctx.campaign, "description", "%PDF-1.7", 415)
    assert %{"error" => _} = upload(ctx.gm, ctx.campaign, "description", "", 415)

    big = :binary.copy(<<0xFF, 0xD8, 0xFF>>, 9_000_000)
    assert %{"error" => _} = upload(ctx.gm, ctx.campaign, "description", big, 413)

    assert %{"error" => _} =
             upload(
               ctx.gm,
               ctx.campaign,
               "description",
               encode(solid(7100, 7100, [0, 0, 0]), ".png"),
               422
             )

    assert %{"error" => _} =
             upload(ctx.gm, ctx.campaign, "description", binary_part(png(), 0, 30), 422)
  end

  test "only the GM can upload; everyone else gets not found", ctx do
    for who <- [ctx.other, ctx.other_gm] do
      assert %{"error" => _} = upload(who, ctx.campaign, "description", png(), 404)
    end

    assert %{"error" => _} = upload(ctx.gm, ctx.campaign, "gm_secrets", png(), 404)
    assert %{"error" => _} = upload(ctx.gm, "not-a-uuid", "description", png(), 404)
    assert %{"error" => _} = upload(ctx.gm, ctx.elsewhere, "description", png(), 404)
  end

  test "anonymous users cannot upload or request URLs", ctx do
    assert %{"error" => "Sign in to continue."} =
             upload(ctx.conn, ctx.campaign, "description", png(), 401)

    %{"id" => id} = upload(ctx.gm, ctx.campaign, "description", png())

    assert %{"error" => "Sign in to continue."} =
             rpc(
               ctx.conn,
               "get_campaign_image_url",
               %{
                 input: %{id: id, campaignId: ctx.campaign, section: "description"}
               },
               401
             )
  end

  test "no signed URL for users without access, or for an image ID in the wrong place", ctx do
    %{"id" => id} = upload(ctx.gm, ctx.campaign, "description", png())

    for who <- [ctx.other, ctx.other_gm] do
      assert %{"success" => false} = url(who, id, ctx.campaign, "description")
    end

    # Copying the ID into another section or campaign finds nothing, even for the GM.
    assert %{"success" => false} = url(ctx.gm, id, ctx.campaign, "progress_rewards")
    assert %{"success" => false} = url(ctx.gm, id, ctx.elsewhere, "description")
    assert %{"success" => false} = url(ctx.other_gm, id, ctx.elsewhere, "description")
  end

  test "a document can only reference images from its own campaign and section", ctx do
    %{"id" => own} = upload(ctx.gm, ctx.campaign, "description", png())
    %{"id" => theirs} = upload(ctx.other_gm, ctx.elsewhere, "description", png())

    assert %{"success" => true} = save(ctx.gm, ctx.campaign, "description", [image_block(own)])

    # Same campaign, other section.
    assert %{"success" => false} =
             save(ctx.gm, ctx.campaign, "progress_rewards", [image_block(own)])

    # Image of another campaign.
    assert %{"success" => false} =
             save(ctx.gm, ctx.campaign, "description", [image_block(theirs)], 1)

    # Unknown image.
    assert %{"success" => false} =
             save(ctx.gm, ctx.campaign, "description", [image_block(Ecto.UUID.generate())], 1)

    assert %{"data" => %{"descriptionRevision" => 1, "progressRewardsRevision" => 0}} =
             rpc(ctx.gm, "get_campaign", %{getBy: %{id: ctx.campaign}, fields: @fields})
  end

  test "signed image URLs reject tampered and expired tokens" do
    key = "campaigns/none/images/missing.webp"

    expired =
      Phoenix.Token.sign(AtlasWeb.Endpoint, "storage-url", key,
        signed_at: System.system_time(:second) - 3600
      )

    for token <- ["garbage", expired] do
      assert build_conn() |> get("/api/images/#{token}") |> response(404)
    end
  end
end
