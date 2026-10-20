defmodule AtlasWeb.SectionImageTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.ImageFixtures
  import AtlasWeb.RpcHelpers

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    ann = register(conn, "ann@example.com")
    bob = register(conn, "bob@example.com")
    outsider = register(conn, "outsider@example.com")

    %{"data" => %{"id" => campaign}} =
      rpc(gm, "create_campaign", %{input: %{name: "Keep"}, fields: ["id"]})

    %{"data" => %{"token" => token}} =
      rpc(gm, "create_invitation", %{input: %{campaignId: campaign}, fields: ["token"]})

    for player <- [ann, bob],
        do: rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    {:ok, gm: gm, ann: ann, bob: bob, outsider: outsider, campaign: campaign}
  end

  defp url(who, kind, parent, section, id) do
    rpc(who, "get_image_url", %{
      input: %{id: id, parentType: kind, parentId: parent, section: section}
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

  defp create_note(who, campaign) do
    %{"data" => %{"id" => id}} =
      rpc(who, "create_note", %{input: %{campaignId: campaign, title: "Note"}, fields: ["id"]})

    id
  end

  defp create_session(who, campaign) do
    %{"data" => %{"id" => id}} =
      rpc(who, "create_session", %{input: %{campaignId: campaign}, fields: ["id"]})

    id
  end

  describe "note bodies" do
    test "follow the note's access: owner and GM while hidden, every player once revealed", ctx do
      note = create_note(ctx.ann, ctx.campaign)

      assert %{"id" => image} = upload_to(ctx.ann, "notes", note, "body", png())
      assert %{"id" => _} = upload_to(ctx.gm, "notes", note, "body", png())
      assert %{"error" => _} = upload_to(ctx.bob, "notes", note, "body", png(), 404)
      assert %{"error" => _} = upload_to(ctx.outsider, "notes", note, "body", png(), 404)

      assert %{"success" => true} = url(ctx.ann, "note", note, "body", image)
      assert %{"success" => true} = url(ctx.gm, "note", note, "body", image)
      assert %{"success" => false} = url(ctx.bob, "note", note, "body", image)
      assert %{"success" => false} = url(ctx.outsider, "note", note, "body", image)

      assert %{"success" => true} =
               rpc(ctx.ann, "reveal_note", %{identity: note, fields: ["id"]})

      assert %{"success" => true} = url(ctx.bob, "note", note, "body", image)
      assert %{"success" => false} = url(ctx.outsider, "note", note, "body", image)
      # A player who may edit the body may add images to it.
      assert %{"id" => _} = upload_to(ctx.bob, "notes", note, "body", png())
    end

    test "a body saves only images uploaded into that note", ctx do
      note = create_note(ctx.gm, ctx.campaign)
      other = create_note(ctx.gm, ctx.campaign)
      %{"id" => own} = upload_to(ctx.gm, "notes", note, "body", png())
      %{"id" => elsewhere} = upload_to(ctx.gm, "notes", other, "body", png())

      save = fn id, blocks, expected ->
        rpc(ctx.gm, "save_note_body", %{
          identity: id,
          input: %{json: blocks, schemaVersion: 1, expectedRevision: expected},
          fields: ["bodyRevision"]
        })
      end

      assert %{"success" => true} = save.(note, [image_block(own)], 0)
      assert %{"success" => false} = save.(note, [image_block(elsewhere)], 1)
      assert %{"success" => false} = save.(note, [image_block(Ecto.UUID.generate())], 1)
    end

    test "an image ID from a note finds nothing under another parent", ctx do
      note = create_note(ctx.gm, ctx.campaign)
      %{"id" => image} = upload_to(ctx.gm, "notes", note, "body", png())

      assert %{"success" => false} = url(ctx.gm, "campaign", ctx.campaign, "description", image)
      assert %{"success" => false} = url(ctx.gm, "note", ctx.campaign, "body", image)
    end
  end

  describe "session sections" do
    test "the log image is readable by players; the prep image only by the GM", ctx do
      session = create_session(ctx.gm, ctx.campaign)

      assert %{"id" => log_image} = upload_to(ctx.gm, "sessions", session, "log", png())
      assert %{"id" => prep_image} = upload_to(ctx.gm, "sessions", session, "prep", png())

      assert %{"success" => true} = url(ctx.gm, "session", session, "log", log_image)
      assert %{"success" => true} = url(ctx.gm, "session", session, "prep", prep_image)
      assert %{"success" => true} = url(ctx.ann, "session", session, "log", log_image)
      assert %{"success" => false} = url(ctx.ann, "session", session, "prep", prep_image)
      assert %{"success" => false} = url(ctx.outsider, "session", session, "log", log_image)
    end

    test "players cannot upload into a session", ctx do
      session = create_session(ctx.gm, ctx.campaign)

      for section <- ["log", "prep"] do
        assert %{"error" => _} = upload_to(ctx.ann, "sessions", session, section, png(), 404)
      end

      assert %{"error" => _} = upload_to(ctx.gm, "sessions", session, "body", png(), 404)
    end

    test "the log and the prep each save only their own images", ctx do
      session = create_session(ctx.gm, ctx.campaign)
      %{"id" => log_image} = upload_to(ctx.gm, "sessions", session, "log", png())

      save = fn action, blocks, expected ->
        rpc(ctx.gm, action, %{
          identity: session,
          input: %{json: blocks, schemaVersion: 1, expectedRevision: expected},
          fields: ["id"]
        })
      end

      assert %{"success" => true} = save.("save_session_log", [image_block(log_image)], 0)
      assert %{"success" => false} = save.("save_session_prep", [image_block(log_image)], 0)
    end
  end
end
