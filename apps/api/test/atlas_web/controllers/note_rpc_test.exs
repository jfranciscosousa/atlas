defmodule AtlasWeb.NoteRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  @fields [
    "id",
    "title",
    "campaignId",
    "bodyJson",
    "bodyRevision",
    "archivedAt",
    "revealed",
    "isOwner",
    "ownerName"
  ]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    other = register(conn, "other@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    assert %{"success" => true, "data" => %{"token" => token}} =
             rpc(gm, "create_invitation", %{
               input: %{campaignId: campaign_id},
               fields: ["token"]
             })

    players =
      for email <- ["ann@example.com", "bob@example.com"] do
        player = register(conn, email)

        assert %{"success" => true} =
                 rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})

        player
      end

    [ann, bob] = players

    {:ok, conn: conn, gm: gm, other: other, ann: ann, bob: bob, campaign_id: campaign_id}
  end

  defp note_action(who, action, id, input \\ %{}),
    do: rpc(who, action, %{identity: id, input: input, fields: @fields})

  defp list(who, campaign_id, archived \\ false) do
    rpc(who, "list_notes", %{
      input: %{campaignId: campaign_id, archived: archived},
      fields: @fields
    })["data"]
  end

  defp readable?(who, id),
    do: rpc(who, "get_note", %{getBy: %{id: id}, fields: @fields})["success"]

  defp create(who, campaign_id, title \\ "The Cult of the Drowned") do
    rpc(who, "create_note", %{input: %{campaignId: campaign_id, title: title}, fields: @fields})
  end

  defp save(email, id, doc \\ [paragraph("hi")], opts \\ []),
    do: Atlas.Fixtures.save_section(Atlas.Content.Note, id, :body, doc, email, opts)

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

    assert {:ok, %{body_revision: 1}} = save("gm@example.com", id)

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{} | _]}} =
             save("gm@example.com", id, [paragraph("hi")], revision: 0)
  end

  test "someone who is not the GM cannot create, list, read, rename, or save", ctx do
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

    assert {:error, %Ash.Error.Forbidden{}} = save("other@example.com", id)

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

  test "a new note is hidden and owned by its creator", ctx do
    assert %{"success" => true, "data" => %{"revealed" => false, "isOwner" => true} = gm_note} =
             create(ctx.gm, ctx.campaign_id)

    assert gm_note["ownerName"]

    assert %{"success" => true, "data" => %{"id" => id, "revealed" => false, "isOwner" => true}} =
             create(ctx.ann, ctx.campaign_id)

    assert %{"data" => %{"isOwner" => false}} =
             rpc(ctx.gm, "get_note", %{getBy: %{id: id}, fields: @fields})
  end

  test "a player's hidden note is read by its owner and the GM, not by other players", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.campaign_id)

    assert readable?(ctx.ann, id)
    assert readable?(ctx.gm, id)
    refute readable?(ctx.bob, id)
    refute readable?(ctx.other, id)
    assert [%{"id" => ^id}] = list(ctx.ann, ctx.campaign_id)
    assert [%{"id" => ^id}] = list(ctx.gm, ctx.campaign_id)
    assert [] = list(ctx.bob, ctx.campaign_id)

    assert {:error, %Ash.Error.Forbidden{}} = save("bob@example.com", id)
    assert %{"success" => false} = note_action(ctx.bob, "reveal_note", id)
  end

  test "the GM's notes stay hidden from players until revealed", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)
    assert [] = list(ctx.ann, ctx.campaign_id)
    refute readable?(ctx.ann, id)

    assert %{"success" => true, "data" => %{"revealed" => true}} =
             note_action(ctx.gm, "reveal_note", id)

    assert [%{"id" => ^id}] = list(ctx.ann, ctx.campaign_id)
    assert readable?(ctx.bob, id)
    refute readable?(ctx.other, id)
    assert [] = list(ctx.other, ctx.campaign_id)

    assert %{"success" => true, "data" => %{"revealed" => false}} =
             note_action(ctx.gm, "hide_note", id)

    refute readable?(ctx.ann, id)
  end

  test "an owner reveals their note; the GM can hide it again", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.campaign_id)
    assert %{"success" => true} = note_action(ctx.ann, "reveal_note", id)
    assert readable?(ctx.bob, id)

    assert %{"success" => true, "data" => %{"revealed" => false}} =
             note_action(ctx.gm, "hide_note", id)

    refute readable?(ctx.bob, id)
    assert readable?(ctx.ann, id)
  end

  test "members edit the body of a revealed note but cannot rename, hide, or archive it", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)
    assert %{"success" => true} = note_action(ctx.gm, "reveal_note", id)

    assert {:ok, %{body_revision: 1}} = save("ann@example.com", id)
    assert {:ok, %{body_revision: 2}} = save("bob@example.com", id)

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{} | _]}} =
             save("ann@example.com", id, [paragraph("hi")], revision: 1)

    for action <- ["hide_note", "archive_note", "restore_note"] do
      assert %{"success" => false} = note_action(ctx.ann, action, id)
    end

    assert %{"success" => false} = note_action(ctx.ann, "rename_note", id, %{title: "x"})

    assert %{"data" => %{"title" => "The Cult of the Drowned", "revealed" => true}} =
             rpc(ctx.gm, "get_note", %{getBy: %{id: id}, fields: @fields})
  end

  test "other players never see an archived note; the owner and the GM do", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.campaign_id)
    assert %{"success" => true} = note_action(ctx.ann, "reveal_note", id)
    assert readable?(ctx.bob, id)

    assert %{"success" => true} = note_action(ctx.ann, "archive_note", id)

    refute readable?(ctx.bob, id)
    assert [] = list(ctx.bob, ctx.campaign_id, true)
    assert [%{"id" => ^id}] = list(ctx.ann, ctx.campaign_id, true)
    assert [%{"id" => ^id}] = list(ctx.gm, ctx.campaign_id, true)
    assert {:error, %Ash.Error.Forbidden{}} = save("bob@example.com", id)

    assert %{"success" => true, "data" => %{"archivedAt" => nil}} =
             note_action(ctx.ann, "restore_note", id)

    assert readable?(ctx.bob, id)
  end

  test "an owner cannot hand a note to another campaign or owner", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.campaign_id)

    assert %{"success" => false} =
             note_action(ctx.ann, "reveal_note", id, %{
               revealed: false,
               ownerId: Ecto.UUID.generate()
             })

    assert %{"success" => false} =
             note_action(ctx.ann, "rename_note", id, %{title: "x", ownerId: Ecto.UUID.generate()})
  end
end
