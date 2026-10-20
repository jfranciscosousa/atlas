defmodule AtlasWeb.ImageTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.ImageFixtures
  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    player = register(conn, "ann@example.com")
    outsider = register(conn, "outsider@example.com")

    %{"data" => %{"id" => campaign}} =
      rpc(gm, "create_campaign", %{input: %{name: "Keep"}, fields: ["id"]})

    %{"data" => %{"token" => token}} =
      rpc(gm, "create_invitation", %{input: %{campaignId: campaign}, fields: ["token"]})

    rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    {:ok, conn: conn, gm: gm, player: player, outsider: outsider, campaign: campaign}
  end

  defp image_url(who, image_id), do: rpc(who, "get_image_url", %{input: %{id: image_id}})

  defp image_block(id) do
    %{
      "id" => "img",
      "type" => "image",
      "props" => %{"url" => "atlas-image:#{id}"},
      "children" => []
    }
  end

  test "the GM uploads an image and loads it through a fresh signed URL", ctx do
    assert %{"id" => id, "width" => 64, "height" => 48, "animated" => false} =
             upload(ctx.gm, png())

    assert %{"success" => true, "data" => "/api/images/" <> _ = signed} = image_url(ctx.gm, id)

    response = get(build_conn(), signed)
    assert response.status == 200
    assert ["image/webp" <> _] = get_resp_header(response, "content-type")
    assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = response.resp_body
  end

  test "a GIF animation survives and an SVG is rasterized", ctx do
    assert %{"animated" => true, "width" => 64, "height" => 48} =
             upload(ctx.gm, animated(".gif"))

    assert %{"animated" => false, "width" => 120, "height" => 80} = upload(ctx.gm, svg())
  end

  test "the server rejects wrong types, oversize files and too many pixels", ctx do
    assert %{"error" => _} = upload(ctx.gm, "%PDF-1.7", 415)
    assert %{"error" => _} = upload(ctx.gm, "", 415)

    big = :binary.copy(<<0xFF, 0xD8, 0xFF>>, 9_000_000)
    assert %{"error" => _} = upload(ctx.gm, big, 413)

    assert %{"error" => _} = upload(ctx.gm, encode(solid(7100, 7100, [0, 0, 0]), ".png"), 422)
    assert %{"error" => _} = upload(ctx.gm, binary_part(png(), 0, 30), 422)
  end

  test "a player can upload; someone who plays in no campaign cannot", ctx do
    assert %{"id" => _} = upload(ctx.player, png())
    assert %{"error" => _} = upload(ctx.outsider, png(), 404)
  end

  test "anyone signed in who has the image ID gets a signed URL; an unknown ID finds nothing",
       ctx do
    %{"id" => id} = upload(ctx.gm, png())

    for who <- [ctx.gm, ctx.player, ctx.outsider] do
      assert %{"success" => true, "data" => "/api/images/" <> _} = image_url(who, id)
    end

    assert %{"success" => false} = image_url(ctx.gm, Ecto.UUID.generate())
  end

  test "anonymous users cannot upload or request URLs", ctx do
    assert %{"error" => "Sign in to continue."} = upload(ctx.conn, png(), 401)
    %{"id" => id} = upload(ctx.gm, png())

    assert %{"error" => "Sign in to continue."} =
             rpc(ctx.conn, "get_image_url", %{input: %{id: id}}, 401)
  end

  test "every rich-text field saves images that exist and rejects ones that do not", ctx do
    %{"id" => image} = upload(ctx.gm, png())
    missing = Ecto.UUID.generate()

    %{"data" => %{"id" => note}} =
      rpc(ctx.gm, "create_note", %{
        input: %{campaignId: ctx.campaign, title: "N"},
        fields: ["id"]
      })

    %{"data" => %{"id" => session}} =
      rpc(ctx.gm, "create_session", %{input: %{campaignId: ctx.campaign}, fields: ["id"]})

    saves = [
      {"save_campaign_description", ctx.campaign},
      {"save_campaign_progress_rewards", ctx.campaign},
      {"save_note_body", note},
      {"save_session_log", session},
      {"save_session_prep", session}
    ]

    for {action, id} <- saves do
      save = fn blocks, expected ->
        rpc(ctx.gm, action, %{
          identity: id,
          input: %{json: blocks, schemaVersion: 1, expectedRevision: expected},
          fields: ["id"]
        })
      end

      assert %{"success" => false} = save.([image_block(missing)], 0)
      assert %{"success" => true} = save.([paragraph("x"), image_block(image)], 0)
    end
  end

  test "signed image URLs reject tampered and expired tokens" do
    key = "images/missing.webp"

    expired =
      Phoenix.Token.sign(AtlasWeb.Endpoint, "storage-url", key,
        signed_at: System.system_time(:second) - 3600
      )

    for token <- ["garbage", expired] do
      assert build_conn() |> get("/api/images/#{token}") |> response(404)
    end
  end
end
