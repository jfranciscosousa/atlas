defmodule AtlasWeb.RichTextChannelTest do
  use AtlasWeb.ConnCase, async: false

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1, paragraph: 2, save_section!: 5]

  import Phoenix.ChannelTest,
    only: [
      assert_push: 2,
      assert_reply: 2,
      assert_reply: 3,
      refute_push: 3,
      subscribe_and_join: 3,
      leave: 1
    ]

  alias Atlas.RichText.Collab.Awareness
  alias Atlas.RichText.Collab.Blocks
  alias AtlasWeb.RichTextSocket

  @endpoint AtlasWeb.Endpoint
  require Ash.Query
  @fragment Blocks.fragment()

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    ann = register(conn, "ann@example.com")
    bob = register(conn, "bob@example.com")
    outsider = register(conn, "out@example.com")

    assert %{"data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    assert %{"data" => %{"token" => token}} =
             rpc(gm, "create_invitation", %{input: %{campaignId: campaign_id}, fields: ["token"]})

    for player <- [ann, bob],
        do:
          assert(
            %{"success" => true} =
              rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})
          )

    assert %{"data" => %{"id" => note_id}} =
             rpc(ann, "create_note", %{
               input: %{campaignId: campaign_id, title: "Ann's"},
               fields: ["id"]
             })

    assert %{"data" => %{"id" => session_id}} =
             rpc(gm, "create_session", %{input: %{campaignId: campaign_id}, fields: ["id"]})

    {:ok,
     gm: gm,
     ann: ann,
     bob: bob,
     outsider: outsider,
     campaign_id: campaign_id,
     note_id: note_id,
     session_id: session_id}
  end

  defp player_description_ref(ctx, email) do
    user = Atlas.Fixtures.user_by_email(email)

    player =
      Atlas.Campaigns.Character
      |> Ash.Query.filter(campaign_id == ^ctx.campaign_id and user_id == ^user.id)
      |> Ash.read_one!(authorize?: false)

    "character:#{player.id}:description"
  end

  # A socket as the browser opens it: the session cookie and the CSRF token of /api/session.
  defp open_socket(conn) do
    {session_conn, _csrf} = csrf(conn)
    session = Plug.Conn.get_session(session_conn)
    Phoenix.ChannelTest.connect(RichTextSocket, %{}, connect_info: %{session: session})
  end

  defp join(conn, ref) do
    {:ok, socket} = open_socket(conn)
    subscribe_and_join(socket, AtlasWeb.RichTextChannel, "doc:" <> ref)
  end

  defp send_frame(socket, event \\ "yjs", message) do
    Phoenix.ChannelTest.push(socket, event, {:binary, Yex.Sync.message_encode!(message)})
  end

  defp send_update(socket, update), do: send_frame(socket, {:sync, {:sync_update, update}})

  # Joins, asks for the document, and returns a client copy of it.
  defp open(conn, ref) do
    {:ok, reply, socket} = join(conn, ref)
    client = Yex.Doc.new()
    {:ok, step1} = Yex.Sync.get_sync_step1(client)
    send_frame(socket, "yjs_sync", {:sync, step1})
    assert_push "yjs", {:binary, <<0, _::binary>> = answer}
    {:ok, {:sync, {:sync_step2, state}}} = Yex.Sync.message_decode(answer)
    :ok = Yex.apply_update(client, state)

    # A writer is also asked what the server lacks. This client has nothing new to say.
    if reply.canWrite do
      assert_push "yjs", {:binary, <<0, _::binary>> = ask}
      assert {:ok, {:sync, {:sync_step1, _}}} = Yex.Sync.message_decode(ask)
    end

    {reply, socket, client}
  end

  # Edits the first paragraph of a client copy and returns the update that results.
  defp edit(client, fun) do
    {:ok, before} = Yex.encode_state_vector(client)
    fragment = Yex.Doc.get_xml_fragment(client, @fragment)
    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    {:ok, container} = Yex.XmlElement.fetch(group, 0)
    {:ok, paragraph} = Yex.XmlElement.fetch(container, 0)
    fun.(%{fragment: fragment, group: group, container: container, paragraph: paragraph})
    {:ok, update} = Yex.encode_state_as_update(client, before)
    update
  end

  defp type(client, text) do
    edit(client, fn %{paragraph: paragraph} ->
      case Yex.XmlElement.fetch(paragraph, 0) do
        {:ok, run} -> Yex.XmlText.insert(run, Yex.XmlText.length(run), text)
        :error -> Yex.XmlElement.push(paragraph, Yex.XmlTextPrelim.from(text))
      end
    end)
  end

  defp text_of(client) do
    {:ok, blocks} = Blocks.project(client)
    blocks |> Enum.flat_map(&(&1["content"] || [])) |> Enum.map_join(& &1["text"])
  end

  defp note(conn, id),
    do: rpc(conn, "get_note", %{getBy: %{id: id}, fields: ["bodyJson", "bodyRevision"]})["data"]

  defp note_ref(ctx), do: "note:#{ctx.note_id}:body"

  defp reveal(ctx),
    do:
      assert(
        %{"success" => true} =
          rpc(ctx.ann, "set_note_visibility", %{
            identity: ctx.note_id,
            input: %{visibility: "everyone"},
            fields: ["id"]
          })
      )

  defp hide(ctx),
    do:
      assert(
        %{"success" => true} =
          rpc(ctx.ann, "set_note_visibility", %{
            identity: ctx.note_id,
            input: %{visibility: "me_and_gm"},
            fields: ["id"]
          })
      )

  describe "editing together" do
    test "an edit is saved as JSON and reaches the other editors", ctx do
      reveal(ctx)
      {%{canWrite: true}, ann, ann_doc} = open(ctx.ann, note_ref(ctx))
      {%{canWrite: true}, _bob, bob_doc} = open(ctx.bob, note_ref(ctx))

      send_update(ann, type(ann_doc, "The keep is flooded."))

      assert_push "yjs", {:binary, <<0, _::binary>> = pushed}
      assert {:ok, {:sync, {:sync_update, update}}} = Yex.Sync.message_decode(pushed)
      :ok = Yex.apply_update(bob_doc, update)
      assert text_of(bob_doc) == "The keep is flooded."

      assert %{"bodyRevision" => 1, "bodyJson" => [%{"content" => [%{"text" => text}]}]} =
               note(ctx.ann, ctx.note_id)

      assert text == "The keep is flooded."
    end

    test "the server answers ok after it stored the update, and for an update that adds nothing",
         ctx do
      reveal(ctx)
      {_, ann, ann_doc} = open(ctx.ann, note_ref(ctx))

      update = type(ann_doc, "Stored.")
      ref = send_update(ann, update)
      assert_reply ref, :ok
      assert %{"bodyRevision" => 1} = note(ctx.ann, ctx.note_id)

      ref = send_update(ann, update)
      assert_reply ref, :ok
      assert %{"bodyRevision" => 1} = note(ctx.ann, ctx.note_id)
    end

    test "concurrent edits from the same base both survive", ctx do
      reveal(ctx)
      {_, ann, ann_doc} = open(ctx.ann, note_ref(ctx))
      {_, bob, bob_doc} = open(ctx.bob, note_ref(ctx))

      send_update(ann, type(ann_doc, "Ann."))
      send_update(bob, type(bob_doc, "Bob."))
      # Each channel handles its own frame; reading the state runs behind both writes.
      _ = :sys.get_state(ann.channel_pid)
      _ = :sys.get_state(bob.channel_pid)

      assert %{"bodyRevision" => 2, "bodyJson" => [%{"content" => content}]} =
               note(ctx.gm, ctx.note_id)

      text = Enum.map_join(content, & &1["text"])
      assert text =~ "Ann." and text =~ "Bob."
    end

    test "edits made offline are uploaded when the editor reconnects", ctx do
      {_, ann, ann_doc} = open(ctx.ann, note_ref(ctx))
      _offline = type(ann_doc, "Written offline.")
      Process.unlink(ann.channel_pid)
      leave(ann)

      # A new connection syncs the same client document: the server asks for what it lacks.
      {:ok, _, socket} = join(ctx.ann, note_ref(ctx))
      {:ok, step1} = Yex.Sync.get_sync_step1(ann_doc)
      send_frame(socket, "yjs_sync", {:sync, step1})
      assert_push "yjs", {:binary, <<0, _::binary>>}
      assert_push "yjs", {:binary, <<0, _::binary>> = ask}
      assert {:ok, {:sync, {:sync_step1, vector}}} = Yex.Sync.message_decode(ask)
      {:ok, diff} = Yex.encode_state_as_update(ann_doc, vector)
      send_frame(socket, {:sync, {:sync_step2, diff}})
      _ = :sys.get_state(socket.channel_pid)

      assert %{"bodyJson" => [%{"content" => [%{"text" => "Written offline."}]}]} =
               note(ctx.ann, ctx.note_id)
    end

    test "a stored document is seeded from its JSON, tables and links included", ctx do
      doc = [
        %{
          "id" => "b1",
          "type" => "paragraph",
          "props" => %{},
          "content" => [
            %{"type" => "text", "text" => "See ", "styles" => %{"bold" => true}},
            %{
              "type" => "link",
              "href" => "https://example.org",
              "content" => [%{"type" => "text", "text" => "here", "styles" => %{}}]
            }
          ],
          "children" => []
        }
      ]

      save_section!(Atlas.Content.Note, ctx.note_id, :body, doc, "ann@example.com")

      {_, _socket, client} = open(ctx.ann, note_ref(ctx))

      assert {:ok, [%{"content" => [%{"text" => "See "}, %{"type" => "link"}]}]} =
               Blocks.project(client)
    end

    test "a JSON save outside live editing resets every editor onto the saved text", ctx do
      {%{epoch: 1}, ann, ann_doc} = open(ctx.ann, note_ref(ctx))
      send_update(ann, type(ann_doc, "Live."))
      _ = :sys.get_state(ann.channel_pid)

      save_section!(
        Atlas.Content.Note,
        ctx.note_id,
        :body,
        [paragraph("Saved elsewhere.")],
        "ann@example.com"
      )

      # The old editor is told to start over. Its next frame never reaches the new document.
      send_update(ann, type(ann_doc, " More."))
      assert_push "reset", %{}

      assert %{"bodyJson" => [%{"content" => [%{"text" => "Saved elsewhere."}]}]} =
               note(ctx.ann, ctx.note_id)

      assert {%{epoch: 2}, _socket, fresh} = open(ctx.ann, note_ref(ctx))
      assert text_of(fresh) == "Saved elsewhere."
    end
  end

  describe "who may open a section" do
    test "a hidden note opens for its owner and the GM only", ctx do
      assert {:ok, %{canWrite: true}, _} = join(ctx.ann, note_ref(ctx))
      assert {:ok, %{canWrite: true}, _} = join(ctx.gm, note_ref(ctx))
      assert {:error, %{reason: "forbidden"}} = join(ctx.bob, note_ref(ctx))
      assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, note_ref(ctx))
    end

    test "revealing a note opens it for the players, hiding closes it again", ctx do
      reveal(ctx)
      assert {:ok, %{canWrite: true}, _} = join(ctx.bob, note_ref(ctx))
      assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, note_ref(ctx))

      hide(ctx)
      assert {:error, %{reason: "forbidden"}} = join(ctx.bob, note_ref(ctx))
    end

    test "the campaign text is the GM's to write and every member's to read", ctx do
      for section <- ["description", "progress_rewards"] do
        ref = "campaign:#{ctx.campaign_id}:#{section}"
        assert {:ok, %{canWrite: true}, _} = join(ctx.gm, ref)
        assert {:ok, %{canWrite: false}, _} = join(ctx.ann, ref)
        assert {:ok, %{canWrite: false}, _} = join(ctx.bob, ref)
        assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, ref)
      end
    end

    test "session prep is the GM's alone; the log is read-only for players", ctx do
      prep = "session:#{ctx.session_id}:prep"
      log = "session:#{ctx.session_id}:log"

      assert {:ok, %{canWrite: true}, _} = join(ctx.gm, prep)
      assert {:error, %{reason: "forbidden"}} = join(ctx.ann, prep)
      assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, prep)

      assert {:ok, %{canWrite: true}, _} = join(ctx.gm, log)
      assert {:ok, %{canWrite: false}, _} = join(ctx.ann, log)
      assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, log)
    end

    test "a player log is written by its author and the GM, read by the other members", ctx do
      assert %{"data" => %{"id" => log_id}} =
               rpc(ctx.ann, "create_player_log", %{
                 input: %{sessionId: ctx.session_id},
                 fields: ["id"]
               })

      ref = "player_log:#{log_id}:body"
      assert {:ok, %{canWrite: true}, _} = join(ctx.ann, ref)
      assert {:ok, %{canWrite: false}, _} = join(ctx.bob, ref)
      assert {:ok, %{canWrite: true}, _} = join(ctx.gm, ref)
      assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, ref)
    end

    test "a character's description is written by its player and the GM, read by every member",
         ctx do
      ref = player_description_ref(ctx, "ann@example.com")

      assert {:ok, %{canWrite: true}, _} = join(ctx.ann, ref)
      assert {:ok, %{canWrite: false}, _} = join(ctx.bob, ref)
      assert {:ok, %{canWrite: true}, _} = join(ctx.gm, ref)
      assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, ref)
    end

    test "a character's secret notes are open to the GM alone", ctx do
      ref =
        String.replace(
          player_description_ref(ctx, "ann@example.com"),
          "description",
          "secret_notes"
        )

      assert {:ok, %{canWrite: true}, _} = join(ctx.gm, ref)
      assert {:error, %{reason: "forbidden"}} = join(ctx.ann, ref)
      assert {:error, %{reason: "forbidden"}} = join(ctx.bob, ref)
      assert {:error, %{reason: "forbidden"}} = join(ctx.outsider, ref)
    end

    test "a section the server cannot build a document from is unavailable, not forbidden", ctx do
      save_section!(
        Atlas.Content.Note,
        ctx.note_id,
        :body,
        [paragraph("x", "an id with spaces")],
        "ann@example.com"
      )

      assert {:error, %{reason: "unavailable"}} = join(ctx.ann, note_ref(ctx))
    end

    test "a topic that does not name a real section is refused", ctx do
      id = ctx.note_id

      for ref <- [
            "note:not-a-uuid:body",
            "note:#{id}:prep",
            "note:#{id}",
            "note:#{id}:body:extra",
            "user:#{id}:body",
            "note:#{Ecto.UUID.generate()}:body",
            ""
          ] do
        assert {:error, %{reason: "forbidden"}} = join(ctx.gm, ref), ref
      end
    end
  end

  describe "a reader cannot write" do
    test "a read-only member's update is refused and stores nothing", ctx do
      ref = "campaign:#{ctx.campaign_id}:description"
      {%{canWrite: false}, ann, ann_doc} = open(ctx.ann, ref)

      ref = send_update(ann, type(ann_doc, "Forged by a player."))
      assert_push "rejected", %{reason: "forbidden"}
      assert_reply ref, :error, %{reason: "forbidden"}

      assert %{
               "success" => true,
               "data" => %{"descriptionJson" => [], "descriptionRevision" => 0}
             } =
               rpc(ctx.gm, "get_campaign", %{
                 getBy: %{id: ctx.campaign_id},
                 fields: ["descriptionJson", "descriptionRevision"]
               })
    end

    test "a reader receives the document but is not asked for edits", ctx do
      ref = "campaign:#{ctx.campaign_id}:description"
      {:ok, _, socket} = join(ctx.ann, ref)
      {:ok, step1} = Yex.Sync.get_sync_step1(Yex.Doc.new())
      send_frame(socket, "yjs_sync", {:sync, step1})
      assert_push "yjs", {:binary, <<0, _::binary>>}
      refute_push "yjs", {:binary, <<0, _::binary>>}, 100
    end
  end

  describe "nobody writes a section the policies keep from them" do
    test "another player cannot write a player's log", ctx do
      assert %{"data" => %{"id" => log_id}} =
               rpc(ctx.ann, "create_player_log", %{
                 input: %{sessionId: ctx.session_id},
                 fields: ["id"]
               })

      ref = "player_log:#{log_id}:body"

      {%{canWrite: false}, socket, doc} = open(ctx.bob, ref)
      send_update(socket, type(doc, "Not mine to write."))
      assert_push "rejected", %{reason: "forbidden"}

      assert %{"data" => [%{"bodyJson" => [], "bodyRevision" => 0}]} =
               rpc(ctx.ann, "list_player_logs", %{
                 input: %{sessionId: ctx.session_id},
                 fields: ["bodyJson", "bodyRevision"]
               })
    end

    test "another player cannot write a character's description", ctx do
      ref = player_description_ref(ctx, "ann@example.com")
      {%{canWrite: false}, socket, doc} = open(ctx.bob, ref)
      send_update(socket, type(doc, "Not mine to write."))
      assert_push "rejected", %{reason: "forbidden"}
    end

    test "a player cannot write the GM's session log", ctx do
      {%{canWrite: false}, socket, doc} = open(ctx.ann, "session:#{ctx.session_id}:log")
      send_update(socket, type(doc, "Rewriting history."))
      assert_push "rejected", %{reason: "forbidden"}

      assert %{"data" => %{"logJson" => [], "logRevision" => 0}} =
               rpc(ctx.gm, "get_session", %{
                 getBy: %{id: ctx.session_id},
                 fields: ["logJson", "logRevision"]
               })
    end
  end

  describe "access ends at once" do
    test "archiving a note closes the channel of a player who had it open", ctx do
      reveal(ctx)
      {_, bob, _} = open(ctx.bob, note_ref(ctx))
      {_, ann, ann_doc} = open(ctx.ann, note_ref(ctx))

      assert %{"success" => true} =
               rpc(ctx.gm, "archive_note", %{identity: ctx.note_id, fields: ["id"]})

      send_update(ann, type(ann_doc, "After the archive."))
      assert_push "revoked", %{}
      _ = bob
    end

    test "a player who lost access cannot read the document either", ctx do
      reveal(ctx)
      {:ok, _, bob} = join(ctx.bob, note_ref(ctx))
      hide(ctx)

      {:ok, step1} = Yex.Sync.get_sync_step1(Yex.Doc.new())
      send_frame(bob, "yjs_sync", {:sync, step1})
      assert_push "revoked", %{}
      refute_push "yjs", {:binary, <<0, _::binary>>}, 100
    end

    test "hiding a note closes the channel of a player who had it open", ctx do
      reveal(ctx)
      {_, ann, ann_doc} = open(ctx.ann, note_ref(ctx))
      {_, _bob, _} = open(ctx.bob, note_ref(ctx))

      hide(ctx)
      send_update(ann, type(ann_doc, "Secret plan."))

      assert_push "revoked", %{}
      refute_push "yjs", {:binary, <<0, _::binary>>}, 100
    end

    test "a player who lost access cannot write any more", ctx do
      reveal(ctx)
      {_, bob, bob_doc} = open(ctx.bob, note_ref(ctx))
      hide(ctx)

      send_update(bob, type(bob_doc, "Still here."))
      assert_push "revoked", %{}
      assert %{"bodyRevision" => 0} = note(ctx.ann, ctx.note_id)
    end

    test "signing out closes the channel", ctx do
      {_, ann, ann_doc} = open(ctx.ann, note_ref(ctx))
      {session, token} = csrf(ctx.ann)

      session
      |> recycle()
      |> put_req_header("x-csrf-token", token)
      |> delete("/api/session")

      send_update(ann, type(ann_doc, "After sign-out."))
      assert_push "revoked", %{}
      assert %{"bodyRevision" => 0} = note(ctx.gm, ctx.note_id)
    end
  end

  describe "hostile frames" do
    setup ctx do
      {_, ann, client} = open(ctx.ann, note_ref(ctx))
      send_update(ann, type(client, "Fine."))
      _ = :sys.get_state(ann.channel_pid)
      {:ok, socket: ann, client: client}
    end

    defp assert_refused(ctx, socket, update, expected) do
      before = note(ctx.ann, ctx.note_id)
      ref = send_update(socket, update)
      assert_push "rejected", %{reason: reason}
      assert reason =~ expected
      assert_reply ref, :error, %{reason: ^reason}
      assert note(ctx.ann, ctx.note_id) == before
    end

    test "an element BlockNote never writes", ctx do
      update =
        edit(ctx.client, fn %{group: group} ->
          Yex.XmlElement.push(group, Yex.XmlElementPrelim.empty("script"))
        end)

      assert_refused(ctx, ctx.socket, update, "block_container")
    end

    test "an attribute that is not a block prop", ctx do
      update =
        edit(ctx.client, fn %{paragraph: paragraph} ->
          Yex.XmlElement.insert_attribute(paragraph, "onclick", "alert(1)")
        end)

      assert_refused(ctx, ctx.socket, update, "attribute")
    end

    test "a link that is not http, https or mailto", ctx do
      update =
        edit(ctx.client, fn %{paragraph: paragraph} ->
          {:ok, run} = Yex.XmlElement.fetch(paragraph, 0)
          Yex.XmlText.format(run, 0, 4, %{"link" => %{"href" => "javascript:alert(1)"}})
        end)

      assert_refused(ctx, ctx.socket, update, "link must use http, https or mailto")
    end

    test "an image that is not an Atlas image", ctx do
      update =
        edit(ctx.client, fn %{group: group} ->
          image = Yex.XmlElementPrelim.new("image", [], %{"url" => "https://evil.example/x.png"})

          Yex.XmlElement.push(
            group,
            Yex.XmlElementPrelim.new("blockContainer", [image], %{"id" => "i1"})
          )
        end)

      assert_refused(ctx, ctx.socket, update, "image url must be an atlas-image reference")
    end

    test "data in another root of the document", ctx do
      update =
        edit(ctx.client, fn _ ->
          Yex.Map.set(Yex.Doc.get_map(ctx.client, "secret"), "x", "y")
        end)

      assert_refused(ctx, ctx.socket, update, "roots")
    end

    test "bytes that are not a Yjs update", ctx do
      assert_refused(ctx, ctx.socket, "not an update", "rejected")
    end

    test "an update larger than the limit", ctx do
      assert_refused(ctx, ctx.socket, :binary.copy(<<0>>, 600_000), "update_too_large")
    end

    test "a state vector that is not one", ctx do
      send_frame(ctx.socket, "yjs_sync", {:sync, {:sync_step1, "garbage"}})
      assert_push "rejected", %{reason: "malformed"}

      # The channel still works afterwards.
      send_update(ctx.socket, type(ctx.client, " More."))
      _ = :sys.get_state(ctx.socket.channel_pid)
      assert %{"bodyRevision" => 2} = note(ctx.ann, ctx.note_id)
    end

    test "a frame that is not part of the protocol", ctx do
      Phoenix.ChannelTest.push(ctx.socket, "yjs", {:binary, <<255, 255, 255>>})
      assert_push "rejected", %{reason: "malformed"}
    end
  end

  describe "presence and cursors" do
    setup ctx do
      for {email, name} <- [
            {"gm@example.com", "GM"},
            {"ann@example.com", "Ann"},
            {"bob@example.com", "Bob"}
          ],
          do: rename!(email, name)

      {:ok, ref: "campaign:#{ctx.campaign_id}:description"}
    end

    defp rename!(email, name) do
      user =
        Atlas.Accounts.User
        |> Ash.Query.filter(email == ^email)
        |> Ash.read_one!(authorize?: false)

      user
      |> Ash.Changeset.for_update(:update_profile, %{display_name: name}, actor: user)
      |> Ash.update!()
    end

    defp position(n), do: %{"type" => %{"client" => 1, "clock" => n}, "assoc" => 0}
    defp cursor(n), do: %{"anchor" => position(n), "head" => position(n)}

    defp send_cursor(socket, n, extra \\ %{}) do
      state = Map.merge(%{"cursor" => cursor(n)}, extra)
      push_raw(socket, Awareness.encode_frame(123, 9_999, state))
    end

    defp push_raw(socket, bytes), do: Phoenix.ChannelTest.push(socket, "yjs", {:binary, bytes})

    defp awareness_id(socket), do: :sys.get_state(socket.channel_pid).assigns.awareness.id

    # Waits until every channel handled what the others sent (twice: a join takes two hops).
    defp settle(sockets),
      do: for(_ <- 1..2, socket <- sockets, do: :sys.get_state(socket.channel_pid))

    # The awareness entries the test process received so far: `{client_id, clock, state}`.
    defp awareness_entries do
      receive do
        %Phoenix.Socket.Message{event: "yjs", payload: {:binary, <<1, _::binary>> = frame}} ->
          {:ok, entries} = Awareness.decode_frame(frame)
          entries ++ awareness_entries()
      after
        0 -> []
      end
    end

    defp joined(conn, ref, sockets \\ []) do
      {:ok, _, socket} = join(conn, ref)
      settle([socket | sockets])
      socket
    end

    test "the server stamps the real name and colour, and ignores a forged identity", ctx do
      gm = joined(ctx.gm, ctx.ref)
      ann = joined(ctx.ann, ctx.ref, [gm])
      awareness_entries()

      forged = %{
        "user" => %{"name" => "Admin", "color" => "#000000", "email" => "root@example.com"},
        "name" => "Admin",
        "color" => "#000000"
      }

      send_cursor(ann, 1, forged)
      settle([gm, ann])

      assert [{id, _clock, state}] = awareness_entries()
      assert id == awareness_id(ann)
      assert state["cursor"] == cursor(1)
      assert Map.keys(state) |> Enum.sort() == ["cursor", "user"]
      assert %{"name" => "Ann", "color" => color} = state["user"]
      assert color in Atlas.RichText.Collab.Presence.palette()
      assert Map.keys(state["user"]) |> Enum.sort() == ["color", "key", "name"]
      refute inspect(state) =~ "Admin"
      refute inspect(state) =~ "example.com"
    end

    test "a client cannot send under the client ID of another channel", ctx do
      gm = joined(ctx.gm, ctx.ref)
      ann = joined(ctx.ann, ctx.ref, [gm])
      bob = joined(ctx.bob, ctx.ref, [gm, ann])
      awareness_entries()

      # The frame claims Bob's ID, and a far clock. The server uses neither.
      forged = Awareness.encode_frame(awareness_id(bob), 4_000_000_000, %{"cursor" => cursor(2)})
      push_raw(ann, forged)
      settle([gm, ann, bob])

      entries = awareness_entries()
      assert entries != []
      assert Enum.uniq(for {id, _, _} <- entries, do: id) == [awareness_id(ann)]
      assert Enum.all?(entries, fn {_, clock, _} -> clock < 1_000 end)
    end

    test "extra keys, oversized and malformed frames are dropped and the channel keeps working",
         ctx do
      gm = joined(ctx.gm, ctx.ref)
      ann = joined(ctx.ann, ctx.ref, [gm])
      awareness_entries()
      monitor = Process.monitor(ann.channel_pid)

      position = position(1)
      valid = cursor(3)

      hostile = [
        Awareness.encode_frame(1, 1, %{"cursor" => Map.put(valid, "extra", 1)}),
        Awareness.encode_frame(1, 1, %{"cursor" => %{valid | "head" => Map.put(position, "x", 1)}}),
        Awareness.encode_frame(1, 1, %{"cursor" => %{"anchor" => "a", "head" => 5}}),
        Awareness.encode_frame(1, 1, %{"cursor" => "text"}),
        Awareness.encode_frame(1, 1, %{"cursor" => valid, "pad" => String.duplicate("a", 2_100)}),
        Awareness.encode_frame(1, 1, "not a map"),
        <<1>>,
        <<1, 255, 255, 255>>,
        <<1, 10, 1, 1, 1>>,
        <<1, 6, 1, 1, 1, 2, 123, 123>>,
        <<1, 7, 1, 1, 1, 2, 123, 125, 0>>,
        <<1>> <> :binary.copy(<<255>>, 3_000)
      ]

      for frame <- hostile, do: push_raw(ann, frame)
      settle([gm, ann])

      assert awareness_entries() == []
      refute_receive {:DOWN, ^monitor, _, _, _}, 50
      refute_receive %Phoenix.Socket.Message{event: "rejected"}, 0

      # The channel still relays a good frame, and text editing still works.
      send_cursor(ann, 3)
      settle([gm, ann])
      assert [{_, _, %{"cursor" => ^valid}}] = awareness_entries()
    end

    test "a channel may send 20 awareness frames per second and no more", ctx do
      gm = joined(ctx.gm, ctx.ref)
      ann = joined(ctx.ann, ctx.ref, [gm])
      awareness_entries()

      for n <- 1..30, do: send_cursor(ann, n)
      settle([gm, ann])

      assert length(awareness_entries()) == 20
      monitor = Process.monitor(ann.channel_pid)
      refute_receive {:DOWN, ^monitor, _, _, _}, 50
    end

    test "a user who lost access receives no awareness and the channel closes", ctx do
      reveal(ctx)
      ann = joined(ctx.ann, note_ref(ctx))
      bob = joined(ctx.bob, note_ref(ctx), [ann])
      awareness_entries()
      bob_id = awareness_id(bob)
      monitor = Process.monitor(bob.channel_pid)

      hide(ctx)
      send_cursor(ann, 1)
      assert_receive {:DOWN, ^monitor, _, _, _}
      assert_push "revoked", %{}
      settle([ann])

      entries = awareness_entries()
      refute Enum.any?(entries, fn {_, _, state} -> state && state["user"]["name"] == "Ann" end)
      # Ann is told to remove Bob.
      assert Enum.any?(entries, fn {id, _, state} -> id == bob_id and is_nil(state) end)
    end

    test "a user who lost access cannot send a cursor", ctx do
      reveal(ctx)
      ann = joined(ctx.ann, note_ref(ctx))
      bob = joined(ctx.bob, note_ref(ctx), [ann])
      awareness_entries()
      monitor = Process.monitor(bob.channel_pid)

      hide(ctx)
      send_cursor(bob, 1)
      assert_receive {:DOWN, ^monitor, _, _, _}
      assert_push "revoked", %{}
      settle([ann])

      entries = awareness_entries()
      refute Enum.any?(entries, fn {_, _, state} -> state && state["cursor"] end)
    end

    test "a channel that leaves tells the others to remove its client ID", ctx do
      gm = joined(ctx.gm, ctx.ref)
      ann = joined(ctx.ann, ctx.ref, [gm])
      send_cursor(ann, 1)
      settle([gm, ann])
      id = awareness_id(ann)
      last_clock = awareness_entries() |> List.last() |> elem(1)
      monitor = Process.monitor(ann.channel_pid)

      Process.unlink(ann.channel_pid)
      leave(ann)
      assert_receive {:DOWN, ^monitor, _, _, _}
      settle([gm])

      assert [{^id, clock, nil}] = awareness_entries()
      assert clock > last_clock
    end

    test "a new channel sees the people who are already here, readers included", ctx do
      gm = joined(ctx.gm, ctx.ref)
      ann = joined(ctx.ann, ctx.ref, [gm])
      send_cursor(ann, 4)
      settle([gm, ann])
      awareness_entries()

      bob = joined(ctx.bob, ctx.ref, [gm, ann])
      entries = awareness_entries()

      names = for {_, _, %{"user" => %{"name" => name}}} <- entries, uniq: true, do: name
      assert Enum.sort(names) == ["Ann", "Bob", "GM"]

      # Bob learns the GM and Ann (with her cursor); the others learn Bob.
      by_id = Map.new(entries, fn {id, _, state} -> {id, state} end)
      assert by_id[awareness_id(gm)]["user"]["name"] == "GM"
      assert by_id[awareness_id(ann)]["cursor"] == cursor(4)
      assert by_id[awareness_id(bob)]["user"]["name"] == "Bob"
      refute inspect(entries) =~ "example.com"
    end

    test "the heartbeat sends the state again under a newer clock", ctx do
      gm = joined(ctx.gm, ctx.ref)
      ann = joined(ctx.ann, ctx.ref, [gm])

      [{_, first, _}] =
        Enum.filter(awareness_entries(), fn {id, _, _} -> id == awareness_id(ann) end)
        |> Enum.take(-1)

      send(ann.channel_pid, :heartbeat)
      settle([gm, ann])

      assert [{_, second, %{"user" => %{"name" => "Ann"}}}] = awareness_entries()
      assert second > first
    end

    test "a reader's cursor reaches the others and the reader still cannot write", ctx do
      gm = joined(ctx.gm, ctx.ref)
      {%{canWrite: false}, ann, ann_doc} = open(ctx.ann, ctx.ref)
      settle([gm, ann])
      awareness_entries()

      send_cursor(ann, 5)
      settle([gm, ann])

      assert [{_, _, %{"cursor" => %{"head" => _}, "user" => %{"name" => "Ann"}}}] =
               awareness_entries()

      ref = send_update(ann, type(ann_doc, "Forged by a reader."))
      assert_push "rejected", %{reason: "forbidden"}
      assert_reply ref, :error, %{reason: "forbidden"}

      assert %{"data" => %{"descriptionJson" => [], "descriptionRevision" => 0}} =
               rpc(ctx.gm, "get_campaign", %{
                 getBy: %{id: ctx.campaign_id},
                 fields: ["descriptionJson", "descriptionRevision"]
               })
    end
  end

  describe "who may connect" do
    test "a signed-out browser and a request without a session are refused", ctx do
      signed_out = Phoenix.ConnTest.build_conn() |> put_req_header("accept", "application/json")
      assert :error = open_socket(signed_out)

      assert :error =
               Phoenix.ChannelTest.connect(RichTextSocket, %{}, connect_info: %{session: nil})

      assert :error = Phoenix.ChannelTest.connect(RichTextSocket, %{}, connect_info: %{})
      assert {:ok, _} = open_socket(ctx.ann)
    end
  end

  test "no RPC action saves a section's JSON: text changes only through live editing" do
    for domain <- [Atlas.Campaigns, Atlas.Content],
        %{resource: resource, rpc_actions: actions} <-
          AshTypescript.Rpc.Info.typescript_rpc(domain) do
      saves = resource |> Atlas.RichText.sections() |> Enum.map(&Atlas.RichText.save_action/1)
      assert Enum.filter(actions, &(&1.action in saves)) == [], inspect(resource)
    end
  end
end
