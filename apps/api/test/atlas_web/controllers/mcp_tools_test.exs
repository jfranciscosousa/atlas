defmodule AtlasWeb.McpToolsTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Fixtures
  alias Atlas.RichText.{Collab, PlainText}

  # A grant with a known token stands in for the OAuth flow, which `McpOAuthTest` covers.
  defp token_for(user) do
    client =
      Ash.create!(Atlas.Mcp.Client, %{redirect_uris: ["https://a.example/cb"]}, authorize?: false)

    token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    Atlas.Mcp.Grant
    |> Ash.create!(
      %{
        user_id: user.id,
        client_id: client.id,
        code_challenge: "unused",
        redirect_uri: "https://a.example/cb"
      },
      authorize?: false
    )
    |> Ash.Changeset.for_update(
      :issue_tokens,
      %{
        access_token_hash: Base.encode16(:crypto.hash(:sha256, token), case: :lower),
        access_expires_at: DateTime.add(DateTime.utc_now(), 600)
      },
      authorize?: false
    )
    |> Ash.update!()

    token
  end

  # Returns the decoded text of the tool result and whether it is an error.
  defp call(token, name, arguments) do
    response =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("accept", "application/json, text/event-stream")
      |> post("/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{name: name, arguments: arguments}
      })
      |> json_response(200)

    %{"content" => [%{"text" => text}], "isError" => error?} = response["result"]
    {error?, text}
  end

  defp ok!(token, name, arguments) do
    assert {false, text} = call(token, name, arguments)
    Jason.decode!(text)
  end

  setup do
    gm = Fixtures.user()
    campaign = Fixtures.campaign(gm)
    session = Ash.create!(Atlas.Campaigns.Session, %{campaign_id: campaign.id}, actor: gm)
    {:ok, gm: gm, token: token_for(gm), campaign: campaign, session: session}
  end

  defp edit(token, kind, id, section, operations, extra \\ %{}) do
    call(token, "edit_blocks", %{
      input: Map.merge(%{kind: kind, id: id, section: section, operations: operations}, extra)
    })
  end

  defp insert(token, kind, id, section, blocks, extra \\ %{}),
    do: edit(token, kind, id, section, [Map.merge(%{op: "insert", blocks: blocks}, extra)])

  defp paragraph(text), do: %{type: "paragraph", content: text}

  defp text(resource, id, section, actor) do
    resource
    |> Ash.get!(id, actor: actor)
    |> Map.fetch!(Atlas.RichText.json_attribute(section))
    |> PlainText.render()
  end

  defp stored(ctx, section \\ :log) do
    ctx.session.id
    |> then(&Ash.get!(Atlas.Campaigns.Session, &1, actor: ctx.gm))
    |> Map.fetch!(Atlas.RichText.json_attribute(section))
  end

  defp join_player(ctx) do
    player = Fixtures.user()

    invitation =
      Ash.create!(Atlas.Campaigns.Invitation, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)

    character =
      Ash.create!(Atlas.Campaigns.Character, %{token: invitation.token},
        action: :join,
        actor: player
      )

    {player, character}
  end

  test "edit_blocks inserts blocks as a live edit that open editors receive", ctx do
    {:ok, target} = Collab.parse("session:#{ctx.session.id}:prep")
    Phoenix.PubSub.subscribe(Atlas.PubSub, Collab.topic(target))

    blocks = [
      %{type: "heading", props: %{level: 1}, content: "Plan"},
      %{
        type: "paragraph",
        content: [
          %{type: "text", text: "The "},
          %{type: "text", text: "twist", styles: %{bold: true}},
          %{type: "text", text: "."}
        ]
      }
    ]

    assert {false, saved} = insert(ctx.token, "session", ctx.session.id, "prep", blocks)

    assert %{"saved" => true, "revision" => 1, "inserted" => [first, second]} =
             Jason.decode!(saved)

    assert first != second
    assert_receive {:collab_update, update} when is_binary(update)

    assert text(Atlas.Campaigns.Session, ctx.session.id, :prep, ctx.gm) == "# Plan\nThe twist."
    assert Ash.get!(Atlas.Campaigns.Session, ctx.session.id, actor: ctx.gm).prep_revision == 1
  end

  test "insert adds to the section, and delete with insert replaces it", ctx do
    insert(ctx.token, "session", ctx.session.id, "log", [paragraph("First")])
    insert(ctx.token, "session", ctx.session.id, "log", [paragraph("Second")])
    assert text(Atlas.Campaigns.Session, ctx.session.id, :log, ctx.gm) == "First\nSecond"

    operations =
      Enum.map(stored(ctx), &%{op: "delete", id: &1["id"]}) ++
        [%{op: "insert", blocks: [paragraph("Only this")]}]

    assert {false, _} = edit(ctx.token, "session", ctx.session.id, "log", operations)
    assert text(Atlas.Campaigns.Session, ctx.session.id, :log, ctx.gm) == "Only this"
    assert [%{"type" => "paragraph"}] = stored(ctx)
  end

  test "an insert into an empty section does not keep the empty paragraph", ctx do
    insert(ctx.token, "session", ctx.session.id, "log", [paragraph("Hello")])
    assert [%{"type" => "paragraph", "content" => [%{"text" => "Hello"}]}] = stored(ctx)
  end

  test "a writer who is not the GM cannot edit the section", ctx do
    stranger_token = token_for(Fixtures.user())

    assert {true, message} =
             insert(stranger_token, "session", ctx.session.id, "prep", [paragraph("Hi")])

    assert message =~ "may write"
    assert text(Atlas.Campaigns.Session, ctx.session.id, :prep, ctx.gm) == ""
  end

  test "a section that the record does not have is refused", ctx do
    assert {true, message} =
             insert(ctx.token, "session", ctx.session.id, "description", [paragraph("Hi")])

    assert message =~ "no such section"
  end

  test "an image that does not exist is refused", ctx do
    image = %{type: "image", props: %{url: "atlas-image:#{Ecto.UUID.generate()}"}}
    assert {true, message} = insert(ctx.token, "session", ctx.session.id, "log", [image])
    assert message =~ "image"
  end

  test "campaign and character text follow the same rules", ctx do
    assert {false, _} =
             insert(ctx.token, "campaign", ctx.campaign.id, "description", [paragraph("A keep.")])

    assert text(Atlas.Campaigns.Campaign, ctx.campaign.id, :description, ctx.gm) == "A keep."
  end

  test "notes: create, write, set visibility, rename, archive and restore", ctx do
    note =
      ok!(ctx.token, "create_note", %{input: %{campaign_id: ctx.campaign.id, title: "Plot"}})

    list = for item <- ["a", "b"], do: %{type: "bulletListItem", content: item}
    assert {false, _} = insert(ctx.token, "note", note["id"], "body", list)
    assert text(Atlas.Content.Note, note["id"], :body, ctx.gm) == "- a\n- b"

    for {tool, input} <- [
          set_note_visibility: %{visibility: "everyone"},
          rename_note: %{title: "Plot 2"},
          archive_note: %{},
          restore_note: %{}
        ] do
      assert {false, _} = call(ctx.token, Atom.to_string(tool), %{id: note["id"], input: input})
    end

    assert %{title: "Plot 2", visibility: :everyone, archived_at: nil} =
             Ash.get!(Atlas.Content.Note, note["id"], actor: ctx.gm)
  end

  test "session tools explain that titles are optional", ctx do
    response =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> ctx.token)
      |> put_req_header("accept", "application/json, text/event-stream")
      |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list"})
      |> json_response(200)

    for name <- ["create_session", "update_session"] do
      tool = Enum.find(response["result"]["tools"], &(&1["name"] == name))
      assert tool["description"] =~ "leave it unset"
      assert tool["description"] =~ "Session <number>"
      assert tool["description"] =~ "Do not invent a title."
    end
  end

  test "sessions and campaigns: create and update details", ctx do
    created = ok!(ctx.token, "create_campaign", %{input: %{name: "New Keep"}})
    assert Ash.get!(Atlas.Campaigns.Campaign, created["id"], actor: ctx.gm).name == "New Keep"

    next = ok!(ctx.token, "create_session", %{input: %{campaign_id: ctx.campaign.id}})
    assert next["number"] == 2
    assert Ash.get!(Atlas.Campaigns.Session, next["id"], actor: ctx.gm).title == nil

    assert {false, _} =
             call(ctx.token, "update_session", %{
               id: next["id"],
               input: %{title: "The Vault", status: "done"}
             })

    assert %{title: "The Vault", status: :done} =
             Ash.get!(Atlas.Campaigns.Session, next["id"], actor: ctx.gm)
  end

  test "the GM reads player logs", ctx do
    player = Fixtures.user()

    invitation =
      Ash.create!(Atlas.Campaigns.Invitation, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)

    Ash.create!(Atlas.Campaigns.Character, %{token: invitation.token},
      action: :join,
      actor: player
    )

    log = Ash.create!(Atlas.Campaigns.PlayerLog, %{session_id: ctx.session.id}, actor: player)

    Fixtures.save_section!(
      Atlas.Campaigns.PlayerLog,
      log.id,
      :body,
      [Fixtures.paragraph("I saw a ghost")],
      player
    )

    listed = ok!(ctx.token, "list_player_logs", %{input: %{session_id: ctx.session.id}})
    assert [%{"id" => id, "author_name" => "Test User"}] = listed

    assert %{"body" => [%{"type" => "paragraph", "content" => [%{"text" => "I saw a ghost"}]}]} =
             ok!(ctx.token, "get_player_log", %{input: %{id: id}})
  end

  test "the GM prepares an unclaimed character through MCP and gets the claim link", ctx do
    created =
      ok!(ctx.token, "create_unclaimed_character", %{
        input: %{campaign_id: ctx.campaign.id, player_label: "Ana"}
      })

    assert %{"player_name" => "Ana", "claim_path" => "/claim/" <> _} = created

    assert %{claimed: false, player_label: "Ana"} =
             Ash.get!(Atlas.Campaigns.Character, created["id"], actor: ctx.gm, load: [:claimed])

    assert {true, _} =
             call(ctx.token, "create_unclaimed_character", %{
               input: %{campaign_id: ctx.campaign.id, player_label: ""}
             })

    # Only the GM of the campaign prepares one.
    player = Fixtures.user()

    assert {true, _} =
             call(token_for(player), "create_unclaimed_character", %{
               input: %{campaign_id: ctx.campaign.id, player_label: "Bo"}
             })
  end

  test "MCP and the app show an unclaimed character the same way", ctx do
    unclaimed =
      Ash.create!(
        Atlas.Campaigns.Character,
        %{campaign_id: ctx.campaign.id, player_label: "Ana"},
        action: :create_unclaimed,
        actor: ctx.gm
      )

    load = [:player_name, :claimed, :claim_path]
    app = Ash.get!(Atlas.Campaigns.Character, unclaimed.id, actor: ctx.gm, load: load)

    assert [%{"player_name" => "Ana", "claimed" => false}] =
             ok!(ctx.token, "list_characters", %{input: %{campaign_id: ctx.campaign.id}})

    assert %{"player_name" => player_name, "claimed" => claimed, "claim_path" => claim_path} =
             ok!(ctx.token, "get_character", %{input: %{id: unclaimed.id}})

    assert {player_name, claimed, claim_path} == {app.player_name, app.claimed, app.claim_path}
    assert "/claim/" <> _ = claim_path

    # A player sees the same name and no link, in the app and through MCP.
    player = Fixtures.user()

    invitation =
      Ash.create!(Atlas.Campaigns.Invitation, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)

    Ash.create!(Atlas.Campaigns.Character, %{token: invitation.token},
      action: :join,
      actor: player
    )

    app = Ash.get!(Atlas.Campaigns.Character, unclaimed.id, actor: player, load: load)
    assert %Ash.ForbiddenField{} = app.claim_path

    assert %{"player_name" => "Ana", "claimed" => false, "claim_path" => nil} =
             ok!(token_for(player), "get_character", %{input: %{id: unclaimed.id}})
  end

  test "MCP and the app show a character note the same way", ctx do
    player = Fixtures.user()

    invitation =
      Ash.create!(Atlas.Campaigns.Invitation, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)

    character =
      Ash.create!(Atlas.Campaigns.Character, %{token: invitation.token},
        action: :join,
        actor: player
      )

    note =
      Ash.create!(
        Atlas.Content.Note,
        %{
          campaign_id: ctx.campaign.id,
          title: "Visions",
          visibility: :character,
          character_id: character.id
        },
        actor: ctx.gm
      )

    private =
      Ash.create!(
        Atlas.Content.Note,
        %{campaign_id: ctx.campaign.id, title: "Dreams", visibility: :only_me},
        actor: player
      )

    for {who, token} <- [{ctx.gm, ctx.token}, {player, token_for(player)}] do
      app = Ash.get!(Atlas.Content.Note, note.id, actor: who, load: [:character_name])

      assert %{"visibility" => "character", "character_name" => name} =
               ok!(token, "get_note", %{input: %{id: note.id}})

      assert name == app.character_name

      listed =
        token
        |> ok!("list_notes", %{input: %{campaign_id: ctx.campaign.id}})
        |> Enum.map(& &1["id"])
        |> Enum.sort()

      expected =
        Atlas.Content.Note
        |> Ash.Query.for_read(:list, %{campaign_id: ctx.campaign.id}, actor: who)
        |> Ash.read!()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert listed == expected
    end

    # The GM reads neither surface's view of a player's only-me note.
    assert {true, _} = call(ctx.token, "get_note", %{input: %{id: private.id}})
    assert {:error, _} = Ash.get(Atlas.Content.Note, private.id, actor: ctx.gm)
  end

  test "upload_image refuses an address inside the server's network", ctx do
    for url <- [
          "http://127.0.0.1/a.png",
          "http://localhost/a.png",
          "http://[::1]/a.png",
          "ftp://x.example/a"
        ] do
      assert {true, message} = call(ctx.token, "upload_image", %{input: %{url: url}})
      assert message =~ "private address" or message =~ "http or https"
    end
  end

  test "upload_image_data stores a base64 image and refuses bad input", ctx do
    png = Atlas.ImageFixtures.png()

    for data <- [Base.encode64(png), "data:image/png;base64," <> Base.encode64(png)] do
      assert %{"id" => id, "block" => %{"type" => "image", "props" => %{"url" => url}}} =
               ok!(ctx.token, "upload_image_data", %{input: %{data: data}})

      assert url == "atlas-image:#{id}"

      assert Ash.get!(Atlas.Images.Image, id, authorize?: false).content_type == "image/webp"
    end

    assert {true, message} = call(ctx.token, "upload_image_data", %{input: %{data: "%%%"}})
    assert message =~ "base64"

    assert {true, message} =
             call(ctx.token, "upload_image_data", %{input: %{data: Base.encode64("not an image")}})

    assert message =~ "image"

    # Someone who plays in no campaign cannot store images.
    outsider = Fixtures.user()

    assert {true, _} =
             call(token_for(outsider), "upload_image_data", %{input: %{data: Base.encode64(png)}})
  end

  describe "read, change and write back" do
    setup ctx do
      %{"id" => image} =
        ok!(ctx.token, "upload_image_data", %{
          input: %{data: Base.encode64(Atlas.ImageFixtures.png())}
        })

      blocks = [
        %{id: "h1", type: "heading", props: %{level: 1}, content: "Act one"},
        %{
          id: "p1",
          type: "paragraph",
          content: [
            %{type: "text", text: "The party met "},
            %{type: "text", text: "Ann", styles: %{bold: true}},
            %{type: "text", text: " and read "},
            %{
              type: "link",
              href: "https://example.com/map",
              content: [%{type: "text", text: "the map"}]
            },
            %{type: "text", text: " in "},
            %{type: "mention", props: %{kind: "session", id: ctx.session.id}}
          ]
        },
        %{
          id: "img",
          type: "image",
          props: %{url: "atlas-image:#{image}", name: "keep.png", caption: "The keep"}
        },
        %{
          id: "l1",
          type: "checkListItem",
          props: %{checked: true},
          content: "Found the key",
          children: [%{id: "l1a", type: "paragraph", content: "Nested"}]
        },
        %{
          id: "u1",
          type: "paragraph",
          props: %{textAlignment: "center"},
          content: [
            %{
              type: "text",
              text: "Underlined words",
              styles: %{underline: true, textColor: "red"}
            }
          ]
        },
        %{id: "d1", type: "divider"},
        %{id: "last", type: "paragraph", content: "Last words."}
      ]

      assert {false, _} = insert(ctx.token, "session", ctx.session.id, "log", blocks)
      {:ok, image: image}
    end

    defp read(ctx), do: ok!(ctx.token, "get_session", %{input: %{id: ctx.session.id}})

    defp block(blocks, id) do
      Enum.find_value(blocks, fn block ->
        if block["id"] == id, do: block, else: block(block["children"] || [], id)
      end)
    end

    test "get_session returns the blocks of the editor, without defaults", ctx do
      session = read(ctx)
      assert session["log_revision"] > 0
      assert ~w(h1 p1 img l1 u1 d1 last) == Enum.map(session["log"], & &1["id"])

      # Default props, empty styles and empty children are left out.
      assert %{"type" => "heading", "props" => %{"level" => 1}} = block(session["log"], "h1")
      refute Map.has_key?(block(session["log"], "p1"), "props")
      refute Map.has_key?(block(session["log"], "p1"), "children")
      assert [%{"text" => "The party met "} = first | _] = block(session["log"], "p1")["content"]
      refute Map.has_key?(first, "styles")

      # Formatting that Markdown could not carry comes back whole.
      assert %{"props" => %{"textAlignment" => "center"}, "content" => [underlined]} =
               block(session["log"], "u1")

      assert underlined["styles"] == %{"underline" => true, "textColor" => "red"}

      assert %{"props" => %{"name" => "keep.png", "caption" => "The keep"}} =
               block(session["log"], "img")

      assert %{"props" => %{"checked" => true}, "children" => [%{"id" => "l1a"}]} =
               block(session["log"], "l1")
    end

    test "a mention has the name that the reader may see", ctx do
      mention = fn session ->
        session["log"] |> block("p1") |> Map.fetch!("content") |> List.last()
      end

      assert %{"props" => %{"label" => "Session 1", "kind" => "session"}} = mention.(read(ctx))

      # A name that a player may not read stays hidden, as in the app.
      {player, _character} = join_player(ctx)

      note =
        Ash.create!(
          Atlas.Content.Note,
          %{campaign_id: ctx.campaign.id, title: "GM secret", visibility: :only_me},
          actor: ctx.gm
        )

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{
                   op: "update",
                   id: "last",
                   content: [%{type: "mention", props: %{kind: "note", id: note.id}}]
                 }
               ])

      label = fn session ->
        session["log"] |> block("last") |> get_in(["content", Access.at(0), "props", "label"])
      end

      assert label.(read(ctx)) == "GM secret"

      player_session = ok!(token_for(player), "get_session", %{input: %{id: ctx.session.id}})
      assert label.(player_session) == "Restricted entry"
      assert player_session["prep"] == nil
    end

    test "writing back what get_session returned loses nothing", ctx do
      session = read(ctx)
      assert {false, _} = insert(ctx.token, "session", ctx.session.id, "prep", session["log"])
      assert stored(ctx, :prep) == stored(ctx, :log)
    end

    test "update changes one block, keeps its id and nested blocks, and leaves the others", ctx do
      before = stored(ctx)
      %{"log" => log, "log_revision" => revision} = read(ctx)

      operation = %{
        op: "update",
        id: "l1",
        content: "Found the silver key",
        hash: block(log, "l1")["hash"]
      }

      assert {false, result} =
               edit(ctx.token, "session", ctx.session.id, "log", [operation], %{
                 expected_revision: revision
               })

      assert Jason.decode!(result)["revision"] > revision

      after_edit = stored(ctx)

      assert block(after_edit, "l1")["content"] |> hd() |> Map.fetch!("text") ==
               "Found the silver key"

      assert [%{"id" => "l1a"}] = block(after_edit, "l1")["children"]
      assert block(after_edit, "l1")["props"]["checked"] == true

      assert Enum.reject(after_edit, &(&1["id"] == "l1")) ==
               Enum.reject(before, &(&1["id"] == "l1"))
    end

    test "update can change the type and merge props", ctx do
      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{op: "update", id: "last", type: "heading", props: %{level: 3}}
               ])

      assert %{
               "type" => "heading",
               "props" => %{"level" => 3},
               "content" => [%{"text" => "Last words."}]
             } =
               block(stored(ctx), "last")
    end

    test "an update with an old hash is refused", ctx do
      hash = block(read(ctx)["log"], "last")["hash"]

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{op: "update", id: "last", content: "Changed by someone"}
               ])

      assert {true, message} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{op: "update", id: "last", content: "Stale", hash: hash}
               ])

      assert message =~ "was edited by someone since you read it"

      assert block(stored(ctx), "last")["content"] |> hd() |> Map.fetch!("text") ==
               "Changed by someone"
    end

    test "insert puts blocks after, before or into a block and returns their ids", ctx do
      operations = [
        %{op: "insert", after: "h1", blocks: [Map.put(paragraph("after"), :id, "n1")]},
        %{op: "insert", before: "h1", blocks: [paragraph("before")]},
        %{op: "insert", parent: "last", blocks: [Map.put(paragraph("child"), :id, "n3")]}
      ]

      assert {false, result} = edit(ctx.token, "session", ctx.session.id, "log", operations)
      assert %{"inserted" => ["n1", _generated, "n3"]} = Jason.decode!(result)

      log = stored(ctx)
      assert PlainText.render(log) =~ "before\n# Act one\nafter\nThe party met"
      assert [%{"id" => "n3"}] = block(log, "last")["children"]
    end

    test "delete removes a block with its nested blocks, and move keeps them", ctx do
      operations = [%{op: "delete", id: "img"}, %{op: "move", id: "l1", after: "last"}]

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", operations, %{
                 remove_images: true
               })

      log = stored(ctx)
      assert ~w(h1 p1 u1 d1 last l1) == Enum.map(log, & &1["id"])
      assert [%{"id" => "l1a"}] = block(log, "l1")["children"]
    end

    test "one failing operation changes nothing", ctx do
      before = stored(ctx)

      operations = [
        %{op: "delete", id: "h1"},
        %{op: "update", id: "does-not-exist", content: "x"}
      ]

      assert {true, message} = edit(ctx.token, "session", ctx.session.id, "log", operations)
      assert message =~ "operations[1]"
      assert message =~ "does-not-exist"
      assert stored(ctx) == before
    end

    test "a block that is not valid names the place and the allowed values", ctx do
      bad_style = %{
        type: "paragraph",
        content: [%{type: "text", text: "x"}, %{type: "text", text: "y", styles: %{shiny: true}}]
      }

      assert {true, message} = insert(ctx.token, "session", ctx.session.id, "log", [bad_style])
      assert message =~ "operations[0]: blocks[0].content[1]"
      assert message =~ ~s(text style "shiny" is not allowed; use bold, italic)

      assert {true, message} =
               insert(ctx.token, "session", ctx.session.id, "log", [%{type: "video"}])

      assert message =~ ~s(block type "video" is not allowed; use paragraph, heading)

      assert {true, message} =
               insert(ctx.token, "session", ctx.session.id, "log", [
                 %{type: "divider", content: "text"}
               ])

      assert message =~ "divider block has no content"

      assert {true, message} =
               edit(ctx.token, "session", ctx.session.id, "log", [%{op: "shuffle"}])

      assert message =~ "not known; use insert, update, delete or move"

      assert {true, message} =
               insert(ctx.token, "session", ctx.session.id, "log", [paragraph("x")], %{
                 after: "h1",
                 before: "h1"
               })

      assert message =~ "only one of after, before and parent"
    end

    test "an edit that removes an image is refused unless remove_images is set", ctx do
      before = stored(ctx)

      for operations <- [
            [%{op: "delete", id: "img"}],
            [%{op: "update", id: "img", type: "paragraph", props: %{url: ""}}]
          ] do
        assert {true, message} = edit(ctx.token, "session", ctx.session.id, "log", operations)
        assert message =~ ctx.image
        assert message =~ "remove_images"
        assert stored(ctx) == before
      end

      # Deleting a block that holds the image counts too.
      nest = %{op: "move", id: "img", parent: "l1"}
      assert {false, _} = edit(ctx.token, "session", ctx.session.id, "log", [nest])

      assert {true, message} =
               edit(ctx.token, "session", ctx.session.id, "log", [%{op: "delete", id: "l1"}])

      assert message =~ "remove_images"
    end

    test "moving an image, or deleting and inserting it again, is not removing it", ctx do
      image = block(stored(ctx), "img")

      operations = [
        %{op: "move", id: "img", after: "last"},
        %{op: "delete", id: "img"},
        %{op: "insert", blocks: [Map.take(image, ["type", "props"])]}
      ]

      assert {false, _} = edit(ctx.token, "session", ctx.session.id, "log", operations)
      assert Atlas.RichText.Document.image_ids(stored(ctx)) == [ctx.image]
    end

    test "an edit that deletes many blocks is refused unless delete_many is set", ctx do
      many = for n <- 1..11, do: %{id: "x#{n}", type: "paragraph", content: "x#{n}"}
      assert {false, _} = insert(ctx.token, "session", ctx.session.id, "log", many)
      before = stored(ctx)

      operations = Enum.map(1..11, &%{op: "delete", id: "x#{&1}"})
      assert {true, message} = edit(ctx.token, "session", ctx.session.id, "log", operations)
      assert message =~ "delete_many"
      assert stored(ctx) == before

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", operations, %{delete_many: true})

      assert length(stored(ctx)) == length(before) - 11
    end

    test "an update that drops bold, links or mentions warns and still applies", ctx do
      %{"log" => log} = read(ctx)
      hash = block(log, "p1")["hash"]

      assert {false, result} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{op: "update", id: "p1", content: "Plain now", hash: hash}
               ])

      assert %{"warnings" => [warning]} = Jason.decode!(result)
      assert warning =~ ~s(operations[0]: block "p1" lost bold, link, mention)
      assert PlainText.render(stored(ctx)) =~ "Plain now"
    end

    test "an update that keeps its styles and sends the hash has no warning", ctx do
      hash = block(read(ctx)["log"], "u1")["hash"]
      styles = %{underline: true, textColor: "red"}

      assert {false, result} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{
                   op: "update",
                   id: "u1",
                   content: [%{type: "text", text: "Still underlined", styles: styles}],
                   hash: hash
                 }
               ])

      assert %{"warnings" => []} = Jason.decode!(result)
    end

    test "an update without a hash warns that an edit of someone could be lost", ctx do
      assert {false, result} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{op: "update", id: "last", content: "No hash"}
               ])

      assert %{"warnings" => [warning]} = Jason.decode!(result)
      assert warning =~ "no hash"
    end

    test "a new block cannot reuse the id of a block", ctx do
      assert {true, message} =
               insert(ctx.token, "session", ctx.session.id, "log", [
                 Map.put(paragraph("x"), :id, "h1")
               ])

      assert message =~ ~s(block id "h1" exists)
    end

    test "an edit with an old revision is refused", ctx do
      old = read(ctx)["log_revision"]

      assert {false, _} =
               insert(ctx.token, "session", ctx.session.id, "log", [paragraph("Newer")])

      assert {true, message} =
               edit(
                 ctx.token,
                 "session",
                 ctx.session.id,
                 "log",
                 [%{op: "insert", blocks: [paragraph("Stale")]}],
                 %{expected_revision: old}
               )

      assert message =~ "changed since you read it"
      refute PlainText.render(stored(ctx)) =~ "Stale"
    end

    test "deleting every block leaves an empty paragraph that the next insert replaces", ctx do
      operations = Enum.map(~w(h1 p1 img l1 u1 d1 last), &%{op: "delete", id: &1})

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", operations, %{
                 remove_images: true
               })

      assert [%{"type" => "paragraph", "content" => []}] = stored(ctx)

      assert {false, _} =
               insert(ctx.token, "session", ctx.session.id, "log", [paragraph("Fresh")])

      assert [%{"content" => [%{"text" => "Fresh"}]}] = stored(ctx)
    end

    test "read_blocks reads some blocks with their nested blocks", ctx do
      assert %{"blocks" => [%{"id" => "l1", "children" => [_]}, %{"id" => "last"}]} =
               ok!(ctx.token, "read_blocks", %{
                 input: %{
                   kind: "session",
                   id: ctx.session.id,
                   section: "log",
                   ids: ["l1", "last"]
                 }
               })

      assert {true, message} =
               call(ctx.token, "read_blocks", %{
                 input: %{kind: "session", id: ctx.session.id, section: "log", ids: ["nope"]}
               })

      assert message =~ "nope"
    end

    test "read_blocks gives an outline in plain text", ctx do
      assert %{"outline" => outline, "revision" => revision} =
               ok!(ctx.token, "read_blocks", %{
                 input: %{kind: "session", id: ctx.session.id, section: "log", outline: true}
               })

      assert revision == read(ctx)["log_revision"]
      assert Enum.map(outline, & &1["id"]) == ~w(h1 p1 img l1 l1a u1 d1 last)

      assert %{"text" => "The party met Ann and read the map in Session 1", "depth" => 0} =
               Enum.find(outline, &(&1["id"] == "p1"))

      assert %{"text" => "[image: keep.png - The keep]"} =
               Enum.find(outline, &(&1["id"] == "img"))

      assert %{"depth" => 1} = Enum.find(outline, &(&1["id"] == "l1a"))
    end

    test "read_blocks follows the read rules of the section", ctx do
      {player, _character} = join_player(ctx)

      assert {true, message} =
               call(token_for(player), "read_blocks", %{
                 input: %{kind: "session", id: ctx.session.id, section: "prep"}
               })

      assert message =~ "may read"
    end
  end

  describe "tables and image layout" do
    setup ctx do
      %{"id" => image} =
        ok!(ctx.token, "upload_image_data", %{
          input: %{data: Base.encode64(Atlas.ImageFixtures.png())}
        })

      cell = fn text, styles -> [%{type: "text", text: text, styles: styles}] end

      table = %{
        id: "t1",
        type: "table",
        props: %{textColor: "red"},
        content: %{
          type: "tableContent",
          columnWidths: [120, nil],
          headerRows: 1,
          rows: [
            %{cells: [cell.("Name", %{bold: true}), cell.("Role", %{bold: true})]},
            %{cells: [cell.("Ann", %{}), cell.("Thief\nwith a limp", %{italic: true})]}
          ]
        }
      }

      picture = %{
        id: "img",
        type: "image",
        props: %{
          url: "atlas-image:#{image}",
          name: "keep.png",
          caption: "The keep",
          previewWidth: 320,
          textAlignment: "center",
          showPreview: false
        }
      }

      blocks = [table, picture, %{id: "after", type: "paragraph", content: "After"}]
      assert {false, _} = insert(ctx.token, "session", ctx.session.id, "log", blocks)
      {:ok, image: image}
    end

    defp layout(ctx, id), do: ctx |> stored() |> block(id)

    test "a table keeps its header, widths, styles and line breaks", ctx do
      table = layout(ctx, "t1")
      assert table["props"] == %{"textColor" => "red"}

      assert %{"headerRows" => 1, "columnWidths" => [120, nil], "rows" => [_, row]} =
               table["content"]

      assert [%{"content" => [%{"text" => "Ann"}]}, %{"content" => limp}] = row["cells"]
      # A line break in a cell is a run of its own, between the styled runs.
      assert [
               %{"text" => "Thief", "styles" => %{"italic" => true}},
               %{"text" => "\n"},
               %{"text" => "with a limp", "styles" => %{"italic" => true}}
             ] = limp

      assert {:ok, _} = Atlas.RichText.Document.cast_input(stored(ctx), [])
    end

    test "writing back a table that get_session returned loses nothing", ctx do
      %{"log" => log} = read(ctx)
      assert {false, _} = insert(ctx.token, "session", ctx.session.id, "prep", log)
      assert stored(ctx, :prep) == stored(ctx, :log)
    end

    test "a table can be updated, moved and read as an outline", ctx do
      %{"log" => log} = read(ctx)
      hash = block(log, "t1")["hash"]

      row = fn a, b -> %{cells: [[%{type: "text", text: a}], [%{type: "text", text: b}]]} end

      operations = [
        %{
          op: "update",
          id: "t1",
          hash: hash,
          content: %{
            type: "tableContent",
            headerRows: 1,
            rows: [row.("Who", "What"), row.("Bo", "Bard")]
          }
        },
        %{op: "move", id: "t1", after: "after"}
      ]

      assert {false, result} = edit(ctx.token, "session", ctx.session.id, "log", operations)
      assert %{"warnings" => []} = Jason.decode!(result)

      assert ~w(img after t1) == Enum.map(stored(ctx), & &1["id"])

      assert %{"props" => %{"textColor" => "red"}, "content" => %{"rows" => [_, second]}} =
               layout(ctx, "t1")

      assert [%{"content" => [%{"text" => "Bo"}]}, %{"content" => [%{"text" => "Bard"}]}] =
               second["cells"]

      assert %{"outline" => outline} =
               ok!(ctx.token, "read_blocks", %{
                 input: %{kind: "session", id: ctx.session.id, section: "log", outline: true}
               })

      assert %{"text" => "Who | What\nBo | Bard"} = Enum.find(outline, &(&1["id"] == "t1"))
    end

    test "a table with cells that are not valid names the place", ctx do
      bad = %{
        type: "table",
        content: %{type: "tableContent", rows: [%{cells: [[%{type: "gif"}]]}]}
      }

      assert {true, message} = insert(ctx.token, "session", ctx.session.id, "log", [bad])

      assert message =~ "blocks[0].content.rows[0].cells[0].content[0]" or
               message =~ "rows[0].cells[0]"
    end

    test "an image keeps its width, alignment and preview setting", ctx do
      assert %{"props" => props} = layout(ctx, "img")

      assert %{
               "previewWidth" => 320,
               "textAlignment" => "center",
               "showPreview" => false,
               "name" => "keep.png",
               "caption" => "The keep"
             } = props

      # What the agent reads has all of it, so it can send all of it back.
      assert %{"props" => ^props} = block(read(ctx)["log"], "img")
    end

    test "changing the caption of an image leaves its width and alignment", ctx do
      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{op: "update", id: "img", props: %{caption: "A new caption"}}
               ])

      assert %{"previewWidth" => 320, "textAlignment" => "center", "showPreview" => false} =
               layout(ctx, "img")["props"]

      assert layout(ctx, "img")["props"]["caption"] == "A new caption"
    end

    test "moving an image keeps its layout and needs no flag", ctx do
      before = layout(ctx, "img")

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "log", [
                 %{op: "move", id: "img", after: "after"}
               ])

      assert ~w(t1 after img) == Enum.map(stored(ctx), & &1["id"])
      assert layout(ctx, "img") == before
    end

    test "an image with a width that is not a number is refused", ctx do
      bad = %{type: "image", props: %{url: "atlas-image:#{ctx.image}", previewWidth: %{a: 1}}}
      assert {true, message} = insert(ctx.token, "session", ctx.session.id, "log", [bad])
      assert message =~ "scalar"
    end
  end

  describe "search" do
    setup ctx do
      {player, character} = join_player(ctx)

      %{"id" => image} =
        ok!(ctx.token, "upload_image_data", %{
          input: %{data: Base.encode64(Atlas.ImageFixtures.png())}
        })

      vault =
        Ash.create!(
          Atlas.Content.Note,
          %{campaign_id: ctx.campaign.id, title: "Zephyr's Vault", visibility: :everyone},
          actor: ctx.gm
        )

      assert {false, _} =
               insert(ctx.token, "note", vault.id, "body", [
                 paragraph("Behind the waterfall lies a hoard.")
               ])

      assert {false, _} =
               insert(ctx.token, "session", ctx.session.id, "log", [
                 %{
                   id: "m1",
                   type: "paragraph",
                   content: [
                     %{type: "text", text: "The party entered "},
                     %{type: "mention", props: %{kind: "note", id: vault.id}},
                     %{type: "text", text: " at dawn."}
                   ]
                 },
                 %{
                   id: "i1",
                   type: "image",
                   props: %{
                     url: "atlas-image:#{image}",
                     name: "map.png",
                     caption: "Waterfall map"
                   }
                 }
               ])

      assert {false, _} =
               insert(ctx.token, "session", ctx.session.id, "prep", [
                 paragraph("The dragon sleeps under the waterfall.")
               ])

      assert {false, _} =
               insert(ctx.token, "character", character.id, "secret_notes", [
                 paragraph("Secretly a dragon in disguise.")
               ])

      {:ok, player: player, vault: vault}
    end

    defp search(token, ctx, query, extra \\ %{}) do
      ok!(token, "search", %{
        input: Map.merge(%{campaign_id: ctx.campaign.id, query: query}, extra)
      })
    end

    test "finds blocks by their words, with plain text for mentions and images", ctx do
      %{"hits" => hits, "more" => false} = search(ctx.token, ctx, "waterfall")

      session = Enum.find(hits, &(&1["kind"] == "session"))
      assert session["title"] == "Session 1"
      assert session["id"] == ctx.session.id

      log = Enum.find(session["sections"], &(&1["section"] == "log"))
      assert [%{"id" => "i1", "text" => "[image: map.png - Waterfall map]"}] = log["blocks"]

      assert Enum.any?(session["sections"], &(&1["section"] == "prep"))
    end

    test "a mention reads as its name, and the name finds the blocks that mention it", ctx do
      %{"hits" => hits} = search(ctx.token, ctx, "zephyr")

      session = Enum.find(hits, &(&1["kind"] == "session"))
      assert [%{"section" => "log", "blocks" => [block]}] = session["sections"]
      assert block == %{"id" => "m1", "text" => "The party entered Zephyr's Vault at dawn."}

      # The note itself matches by its title.
      assert Enum.any?(hits, &(&1["kind"] == "note" and &1["id"] == ctx.vault.id))
    end

    test "every word must occur, in any order, and case does not matter", ctx do
      assert %{"hits" => [_ | _]} = search(ctx.token, ctx, "HOARD   behind")
      assert %{"hits" => []} = search(ctx.token, ctx, "hoard dragon")
    end

    test "the name of the entry counts together with its text", ctx do
      assert %{"hits" => hits} = search(ctx.token, ctx, "vault hoard")
      assert [%{"kind" => "note", "sections" => [%{"section" => "body"}]}] = hits
    end

    test "a player does not find what the GM alone reads", ctx do
      assert %{"hits" => hits} = search(ctx.token, ctx, "dragon")
      assert Enum.map(hits, & &1["kind"]) |> Enum.sort() == ["character", "session"]

      player_token = token_for(ctx.player)
      assert %{"hits" => []} = search(player_token, ctx, "dragon")
      assert %{"hits" => [_ | _]} = search(player_token, ctx, "waterfall")
    end

    test "kinds and limit narrow the result", ctx do
      assert %{"hits" => [%{"kind" => "note"}]} =
               search(ctx.token, ctx, "waterfall", %{kinds: ["note"]})

      assert %{"hits" => [_], "more" => true} = search(ctx.token, ctx, "waterfall", %{limit: 1})
    end

    test "global search includes member campaigns and supports an optional campaign filter",
         ctx do
      second = Fixtures.campaign(ctx.player, "Waterfall shores")
      Fixtures.campaign(Fixtures.user(), "Waterfall forbidden")
      player_token = token_for(ctx.player)

      %{"hits" => hits} = ok!(player_token, "search", %{input: %{query: "waterfall"}})

      assert MapSet.new(Enum.map(hits, & &1["campaign_id"])) ==
               MapSet.new([ctx.campaign.id, second.id])

      assert Enum.all?(hits, &is_binary(&1["campaign_name"]))

      assert %{"hits" => [%{"id" => id}]} =
               ok!(player_token, "search", %{
                 input: %{query: "waterfall", campaign_id: second.id}
               })

      assert id == second.id
    end

    test "normalization and typo tolerance apply to titles and snippets", ctx do
      note =
        Ash.create!(
          Atlas.Content.Note,
          %{
            campaign_id: ctx.campaign.id,
            title: "Café—São’s Ｖａｕｌｔ"
          },
          actor: ctx.gm
        )

      Fixtures.save_section!(
        Atlas.Content.Note,
        note.id,
        :body,
        [Fixtures.paragraph(String.duplicate("Before ", 90) <> "café waterfall after")],
        ctx.gm
      )

      assert %{"hits" => [%{"id" => id}]} = search(ctx.token, ctx, "CAFE sao's vault")
      assert id == note.id
      %{"hits" => hits} = search(ctx.token, ctx, "waterfal")
      hit = Enum.find(hits, &(&1["id"] == note.id))
      assert [%{"blocks" => [%{"text" => snippet}]}] = hit["sections"]
      assert snippet =~ "waterfall"
      assert snippet =~ "café"
      assert %{"hits" => [_ | _]} = search(ctx.token, ctx, "watrfall")
      assert %{"hits" => []} = search(ctx.token, ctx, "zzzzzzzz")
    end

    test "normalized exact matches rank before fuzzy title matches", ctx do
      note =
        Ash.create!(
          Atlas.Content.Note,
          %{
            campaign_id: ctx.campaign.id,
            title: "Waterfal"
          },
          actor: ctx.gm
        )

      %{"hits" => hits} = search(ctx.token, ctx, "waterfall")
      assert List.last(hits)["id"] == note.id
    end

    test "global fuzzy search excludes private notes, archived notes and restricted mention names",
         ctx do
      private =
        Ash.create!(
          Atlas.Content.Note,
          %{
            campaign_id: ctx.campaign.id,
            title: "Obsidian sanctuary",
            visibility: :only_me
          },
          actor: ctx.player
        )

      archived =
        Ash.create!(
          Atlas.Content.Note,
          %{
            campaign_id: ctx.campaign.id,
            title: "Obsidian archive",
            visibility: :everyone
          },
          actor: ctx.gm
        )

      Ash.update!(archived, %{}, action: :archive, actor: ctx.gm)

      insert(ctx.token, "session", ctx.session.id, "log", [
        %{
          type: "paragraph",
          content: [%{type: "mention", props: %{kind: "note", id: private.id}}]
        }
      ])

      assert %{"hits" => [], "more" => false} =
               ok!(ctx.token, "search", %{input: %{query: "obsidan", limit: 1}})

      assert %{"hits" => player_hits} =
               ok!(token_for(ctx.player), "search", %{input: %{query: "obsidan"}})

      assert Enum.any?(player_hits, &(&1["id"] == private.id))
      assert Enum.any?(player_hits, &(&1["id"] == ctx.session.id))

      assert %{"hits" => [], "more" => false} =
               ok!(token_for(ctx.player), "search", %{input: %{query: "dragn"}})
    end

    test "global search follows every note visibility level", ctx do
      other = Fixtures.user()

      invitation =
        Atlas.Campaigns.Invitation
        |> Ash.Query.for_read(:active, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)
        |> Ash.read_one!()

      Ash.create!(Atlas.Campaigns.Character, %{token: invitation.token},
        action: :join,
        actor: other
      )

      character =
        Atlas.Campaigns.Character
        |> Ash.Query.for_read(:list, %{campaign_id: ctx.campaign.id}, actor: ctx.player)
        |> Ash.read!()
        |> Enum.find(&(&1.user_id == ctx.player.id))

      notes =
        for visibility <- [:only_me, :me_and_gm, :character, :everyone], into: %{} do
          note =
            Ash.create!(
              Atlas.Content.Note,
              %{
                campaign_id: ctx.campaign.id,
                title: "Sapphire #{visibility}",
                visibility: if(visibility == :character, do: :me_and_gm, else: visibility)
              },
              actor: other
            )

          if visibility == :character do
            Ash.update!(note, %{visibility: :character, character_id: character.id},
              action: :set_visibility,
              actor: ctx.gm
            )
          end

          {visibility, note.id}
        end

      for {actor, visible} <- [
            {other, [:only_me, :me_and_gm, :character, :everyone]},
            {ctx.gm, [:me_and_gm, :character, :everyone]},
            {ctx.player, [:character, :everyone]},
            {Fixtures.user(), []}
          ] do
        %{"hits" => hits} = ok!(token_for(actor), "search", %{input: %{query: "sapphir"}})

        assert MapSet.new(Enum.map(hits, & &1["id"])) ==
                 MapSet.new(Enum.map(visible, &Map.fetch!(notes, &1)))
      end
    end

    test "search requires an authenticated actor" do
      assert {:error, _} =
               Atlas.Search.Request
               |> Ash.ActionInput.for_action(:search, %{query: "waterfall"})
               |> Ash.run_action()
    end

    test "global search resolves mentions within their own campaign", ctx do
      other = Fixtures.campaign(ctx.gm, "Other campaign")

      note =
        Ash.create!(
          Atlas.Content.Note,
          %{
            campaign_id: other.id,
            title: "Moonstone",
            visibility: :everyone
          },
          actor: ctx.gm
        )

      insert(ctx.token, "session", ctx.session.id, "log", [
        %{type: "paragraph", content: [%{type: "mention", props: %{kind: "note", id: note.id}}]}
      ])

      assert %{"hits" => [%{"id" => id}]} =
               ok!(ctx.token, "search", %{input: %{query: "moonstone"}})

      assert id == note.id
    end

    test "the app RPC and MCP return identical results", ctx do
      conn = build_conn() |> put_req_header("accept", "application/json")
      signed_in = AtlasWeb.RpcHelpers.confirm_email(conn)
      actor = ctx.gm
      campaign = Fixtures.campaign(actor, "Café waterfall")
      token = token_for(actor)

      for input <- [%{query: "cafe"}, %{query: "waterfal", campaignId: campaign.id}] do
        assert %{"success" => true, "data" => data} =
                 AtlasWeb.RpcHelpers.rpc(signed_in, "search", %{input: input})

        mcp_input =
          if input[:campaignId],
            do: %{query: input.query, campaign_id: input.campaignId},
            else: input

        assert data == ok!(token, "search", %{input: mcp_input})
      end
    end

    test "an empty query and a campaign that is not yours are refused", ctx do
      assert {true, message} =
               call(ctx.token, "search", %{input: %{campaign_id: ctx.campaign.id, query: "  "}})

      assert message =~ "query"

      assert {true, _} = call(ctx.token, "search", %{input: %{query: "✨ — !!!"}})
      assert {true, _} = call(ctx.token, "search", %{input: %{query: String.duplicate("a", 201)}})

      stranger = token_for(Fixtures.user())

      assert {true, message} =
               call(stranger, "search", %{input: %{campaign_id: ctx.campaign.id, query: "dragon"}})

      assert message =~ "not a campaign that you can read"
    end
  end

  test "the tool descriptions name every block type, style and prop of the schema" do
    for text <- [Atlas.Mcp.Guide.edit_blocks(), Atlas.Mcp.Guide.read_blocks()] do
      for type <- Atlas.RichText.Document.block_types(), do: assert(text =~ type)
      for style <- Atlas.RichText.Document.styles(), do: assert(text =~ style)

      for prop <- Atlas.RichText.Collab.Blocks.props() |> Map.values() |> List.flatten(),
          do: assert(text =~ prop)
    end
  end
end
