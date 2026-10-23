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
    "visibility",
    "characterName",
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

  defp set_visibility(who, id, visibility, extra \\ %{}),
    do: note_action(who, "set_note_visibility", id, Map.put(extra, :visibility, visibility))

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
    assert %{
             "success" => true,
             "data" => %{"visibility" => "me_and_gm", "isOwner" => true} = gm_note
           } =
             create(ctx.gm, ctx.campaign_id)

    assert gm_note["ownerName"]

    assert %{
             "success" => true,
             "data" => %{"id" => id, "visibility" => "me_and_gm", "isOwner" => true}
           } =
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
    assert %{"success" => false} = set_visibility(ctx.bob, id, "everyone")
  end

  test "the GM's notes stay hidden from players until revealed", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)
    assert [] = list(ctx.ann, ctx.campaign_id)
    refute readable?(ctx.ann, id)

    assert %{"success" => true, "data" => %{"visibility" => "everyone"}} =
             set_visibility(ctx.gm, id, "everyone")

    assert [%{"id" => ^id}] = list(ctx.ann, ctx.campaign_id)
    assert readable?(ctx.bob, id)
    refute readable?(ctx.other, id)
    assert [] = list(ctx.other, ctx.campaign_id)

    assert %{"success" => true, "data" => %{"visibility" => "me_and_gm"}} =
             set_visibility(ctx.gm, id, "me_and_gm")

    refute readable?(ctx.ann, id)
  end

  test "an owner reveals their note; the GM can hide it again", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.campaign_id)
    assert %{"success" => true} = set_visibility(ctx.ann, id, "everyone")
    assert readable?(ctx.bob, id)

    assert %{"success" => true, "data" => %{"visibility" => "me_and_gm"}} =
             set_visibility(ctx.gm, id, "me_and_gm")

    refute readable?(ctx.bob, id)
    assert readable?(ctx.ann, id)
  end

  test "members edit the body of a revealed note but cannot rename, hide, or archive it", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.gm, ctx.campaign_id)
    assert %{"success" => true} = set_visibility(ctx.gm, id, "everyone")

    assert {:ok, %{body_revision: 1}} = save("ann@example.com", id)
    assert {:ok, %{body_revision: 2}} = save("bob@example.com", id)

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{} | _]}} =
             save("ann@example.com", id, [paragraph("hi")], revision: 1)

    assert %{"success" => false} = set_visibility(ctx.ann, id, "me_and_gm")

    for action <- ["archive_note", "restore_note"] do
      assert %{"success" => false} = note_action(ctx.ann, action, id)
    end

    assert %{"success" => false} = note_action(ctx.ann, "rename_note", id, %{title: "x"})

    assert %{"data" => %{"title" => "The Cult of the Drowned", "visibility" => "everyone"}} =
             rpc(ctx.gm, "get_note", %{getBy: %{id: id}, fields: @fields})
  end

  test "other players never see an archived note; the owner and the GM do", ctx do
    assert %{"data" => %{"id" => id}} = create(ctx.ann, ctx.campaign_id)
    assert %{"success" => true} = set_visibility(ctx.ann, id, "everyone")
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
             note_action(ctx.ann, "set_note_visibility", id, %{
               visibility: "me_and_gm",
               ownerId: Ecto.UUID.generate()
             })

    assert %{"success" => false} =
             note_action(ctx.ann, "rename_note", id, %{title: "x", ownerId: Ecto.UUID.generate()})
  end

  defp create_with(who, ctx, input) do
    rpc(who, "create_note", %{
      input: Map.merge(%{campaignId: ctx.campaign_id, title: "Visions"}, input),
      fields: @fields
    })
  end

  defp my_character(who, ctx) do
    %{"data" => characters} =
      rpc(who, "list_characters", %{
        input: %{campaignId: ctx.campaign_id},
        fields: ["id", "isMine"]
      })

    Enum.find(characters, & &1["isMine"])["id"]
  end

  test "a player's only-me note is read by nobody else, not even the GM", ctx do
    assert %{"success" => true, "data" => %{"id" => id, "visibility" => "only_me"}} =
             create_with(ctx.ann, ctx, %{visibility: "only_me"})

    assert readable?(ctx.ann, id)
    refute readable?(ctx.gm, id)
    refute readable?(ctx.bob, id)
    assert [] = list(ctx.gm, ctx.campaign_id)
    assert {:error, %Ash.Error.Forbidden{}} = save("gm@example.com", id)
    assert %{"success" => false} = note_action(ctx.gm, "archive_note", id)
    assert %{"success" => false} = set_visibility(ctx.gm, id, "everyone")

    assert %{"success" => true} = set_visibility(ctx.ann, id, "me_and_gm")
    assert readable?(ctx.gm, id)
  end

  test "the GM's only-me note is read by the GM alone", ctx do
    assert %{"data" => %{"id" => id}} = create_with(ctx.gm, ctx, %{visibility: "only_me"})
    assert readable?(ctx.gm, id)
    refute readable?(ctx.ann, id)
  end

  test "a character note is read and edited by the GM and the character's player only", ctx do
    character_id = my_character(ctx.ann, ctx)

    assert %{"success" => true} =
             rpc(ctx.ann, "rename_character", %{
               identity: character_id,
               input: %{name: "Brann"},
               fields: ["id"]
             })

    assert %{"success" => true, "data" => %{"id" => id, "characterName" => "Brann"}} =
             create_with(ctx.gm, ctx, %{visibility: "character", characterId: character_id})

    assert readable?(ctx.ann, id)
    assert [%{"id" => ^id}] = list(ctx.ann, ctx.campaign_id)
    refute readable?(ctx.bob, id)
    assert [] = list(ctx.bob, ctx.campaign_id)

    assert {:ok, _} = save("ann@example.com", id)
    assert {:error, %Ash.Error.Forbidden{}} = save("bob@example.com", id)

    assert %{"success" => false} = note_action(ctx.ann, "rename_note", id, %{title: "x"})
    assert %{"success" => false} = set_visibility(ctx.ann, id, "everyone")
    assert %{"success" => false} = note_action(ctx.ann, "archive_note", id)

    # The player no longer reads an archived character note.
    assert %{"success" => true} = note_action(ctx.gm, "archive_note", id)
    refute readable?(ctx.ann, id)
  end

  test "a character note needs a character of the campaign, and a player links only their own",
       ctx do
    assert %{"success" => false} = create_with(ctx.gm, ctx, %{visibility: "character"})

    ann_character = my_character(ctx.ann, ctx)
    bob_character = my_character(ctx.bob, ctx)

    assert %{"success" => true} =
             create_with(ctx.ann, ctx, %{visibility: "character", characterId: ann_character})

    assert %{"success" => false} =
             create_with(ctx.ann, ctx, %{visibility: "character", characterId: bob_character})

    assert %{"success" => false} =
             create_with(ctx.gm, ctx, %{
               visibility: "character",
               characterId: Ecto.UUID.generate()
             })

    # A note may link a character at any level. The link alone grants no access.
    assert %{"success" => true, "data" => %{"id" => id}} =
             create_with(ctx.gm, ctx, %{visibility: "me_and_gm", characterId: ann_character})

    refute readable?(ctx.ann, id)
  end

  test "a character note for an unclaimed character is the GM's until a player claims it", ctx do
    assert %{"data" => %{"id" => character_id, "claimPath" => "/claim/" <> token}} =
             rpc(ctx.gm, "create_unclaimed_character", %{
               input: %{campaignId: ctx.campaign_id, playerLabel: "Cy"},
               fields: ["id", "claimPath"]
             })

    assert %{"data" => %{"id" => id}} =
             create_with(ctx.gm, ctx, %{visibility: "character", characterId: character_id})

    refute readable?(ctx.ann, id)
    refute readable?(ctx.other, id)

    assert %{"success" => true} =
             rpc(ctx.other, "claim_character", %{input: %{token: token}, fields: ["id"]})

    assert readable?(ctx.other, id)
    refute readable?(ctx.ann, id)
  end
end
