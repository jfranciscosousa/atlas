defmodule AtlasWeb.NoteRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  @fields ["id", "title", "campaignId", "bodyJson", "bodyRevision", "archivedAt"]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    other = register(conn, "other@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    {:ok, conn: conn, gm: gm, other: other, campaign_id: campaign_id}
  end

  defp create(who, campaign_id, title \\ "The Cult of the Drowned") do
    rpc(who, "create_note", %{input: %{campaignId: campaign_id, title: title}, fields: @fields})
  end

  defp save(who, id, expected, doc \\ [paragraph("hi")]) do
    rpc(who, "save_note_body", %{
      identity: id,
      input: %{json: doc, schemaVersion: 1, expectedRevision: expected},
      fields: @fields
    })
  end

  test "the GM creates, lists, reads, renames, and saves a note", ctx do
    assert %{"success" => true, "data" => %{"id" => id, "bodyJson" => [], "bodyRevision" => 0}} =
             create(ctx.gm, ctx.campaign_id)

    assert %{"success" => true, "data" => [%{"id" => ^id}]} =
             rpc(ctx.gm, "list_notes", %{input: %{campaignId: ctx.campaign_id}, fields: @fields})

    assert %{"success" => true, "data" => %{"campaignId" => campaign_id}} =
             rpc(ctx.gm, "get_note", %{getBy: %{id: id}, fields: @fields})

    assert campaign_id == ctx.campaign_id

    assert %{"success" => true, "data" => %{"title" => "Renamed"}} =
             rpc(ctx.gm, "rename_note", %{
               identity: id,
               input: %{title: "Renamed"},
               fields: @fields
             })

    assert %{"success" => true, "data" => %{"bodyRevision" => 1}} = save(ctx.gm, id, 0)

    assert %{"success" => false, "errors" => [%{"type" => "stale_revision"} | _]} =
             save(ctx.gm, id, 0)
  end

  test "someone who is not the GM cannot create, list, read, rename, or save: not found", ctx do
    assert %{"success" => true, "data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    assert %{"success" => false, "errors" => [%{"type" => type} | _]} =
             create(ctx.other, ctx.campaign_id)

    assert type in ["forbidden", "not_found"]

    assert %{"success" => true, "data" => []} =
             rpc(ctx.other, "list_notes", %{
               input: %{campaignId: ctx.campaign_id},
               fields: @fields
             })

    assert %{"success" => false, "errors" => [%{"type" => "not_found"} | _]} =
             rpc(ctx.other, "get_note", %{getBy: %{id: id}, fields: @fields})

    assert %{"success" => false} =
             rpc(ctx.other, "rename_note", %{identity: id, input: %{title: "x"}, fields: @fields})

    assert %{"success" => false} = save(ctx.other, id, 0)

    assert %{"data" => %{"title" => "The Cult of the Drowned", "bodyRevision" => 0}} =
             rpc(ctx.gm, "get_note", %{getBy: %{id: id}, fields: @fields})
  end

  test "archiving removes a note from the list, restoring brings it back, and it stays readable",
       ctx do
    assert %{"success" => true, "data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    list = fn archived ->
      rpc(ctx.gm, "list_notes", %{
        input: %{campaignId: ctx.campaign_id, archived: archived},
        fields: @fields
      })["data"]
    end

    assert %{"success" => true, "data" => %{"archivedAt" => at}} =
             rpc(ctx.gm, "archive_note", %{identity: id, fields: @fields})

    assert at
    assert [] = list.(false)
    assert [%{"id" => ^id}] = list.(true)

    assert %{"success" => true, "data" => %{"id" => ^id}} =
             rpc(ctx.gm, "get_note", %{getBy: %{id: id}, fields: @fields})

    assert %{"success" => true, "data" => %{"archivedAt" => nil}} =
             rpc(ctx.gm, "restore_note", %{identity: id, fields: @fields})

    assert [%{"id" => ^id}] = list.(false)
    assert [] = list.(true)
  end

  test "someone who is not the GM cannot archive or restore a note", ctx do
    assert %{"success" => true, "data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    for action <- ["archive_note", "restore_note"] do
      assert %{"success" => false} =
               rpc(ctx.other, action, %{identity: id, fields: @fields})
    end

    assert %{"data" => %{"archivedAt" => nil}} =
             rpc(ctx.gm, "get_note", %{getBy: %{id: id}, fields: @fields})
  end

  test "a note cannot be moved to another campaign", ctx do
    assert %{"success" => true, "data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    assert %{"success" => false} =
             rpc(ctx.gm, "rename_note", %{
               identity: id,
               input: %{title: "x", campaignId: Ecto.UUID.generate()},
               fields: @fields
             })
  end

  test "a body cannot reference an image", ctx do
    assert %{"success" => true, "data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)

    image = %{
      "id" => "i1",
      "type" => "image",
      "props" => %{"url" => "atlas-image:#{Ecto.UUID.generate()}"},
      "children" => []
    }

    assert %{"success" => false} = save(ctx.gm, id, 0, [image])
  end

  test "an empty title is rejected and anonymous requests are refused", ctx do
    assert %{"success" => false} = create(ctx.gm, ctx.campaign_id, "   ")

    assert %{"error" => "Sign in to continue."} =
             rpc(
               ctx.conn,
               "list_notes",
               %{input: %{campaignId: ctx.campaign_id}, fields: @fields},
               401
             )
  end
end
