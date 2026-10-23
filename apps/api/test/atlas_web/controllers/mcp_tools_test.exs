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

  defp write(token, kind, id, section, markdown, mode \\ "replace") do
    call(token, "write_text", %{
      input: %{kind: kind, id: id, section: section, markdown: markdown, mode: mode}
    })
  end

  defp text(resource, id, section, actor) do
    resource
    |> Ash.get!(id, actor: actor)
    |> Map.fetch!(Atlas.RichText.json_attribute(section))
    |> PlainText.render()
  end

  test "write_text writes Markdown as a live edit that open editors receive", ctx do
    {:ok, target} = Collab.parse("session:#{ctx.session.id}:prep")
    Phoenix.PubSub.subscribe(Atlas.PubSub, Collab.topic(target))

    assert {false, saved} =
             write(ctx.token, "session", ctx.session.id, "prep", "# Plan\n\nThe **twist**.")

    assert Jason.decode!(saved)["saved"] == true
    assert_receive {:collab_update, update} when is_binary(update)

    assert text(Atlas.Campaigns.Session, ctx.session.id, :prep, ctx.gm) == "# Plan\nThe twist."
    assert Ash.get!(Atlas.Campaigns.Session, ctx.session.id, actor: ctx.gm).prep_revision == 1
  end

  test "append adds to the section and replace overwrites it", ctx do
    write(ctx.token, "session", ctx.session.id, "log", "First")
    write(ctx.token, "session", ctx.session.id, "log", "Second", "append")
    assert text(Atlas.Campaigns.Session, ctx.session.id, :log, ctx.gm) == "First\nSecond"

    write(ctx.token, "session", ctx.session.id, "log", "Only this")
    assert text(Atlas.Campaigns.Session, ctx.session.id, :log, ctx.gm) == "Only this"
  end

  test "an append to an empty section does not keep the empty paragraph", ctx do
    write(ctx.token, "session", ctx.session.id, "log", "Hello", "append")
    session = Ash.get!(Atlas.Campaigns.Session, ctx.session.id, actor: ctx.gm)
    assert [%{"type" => "paragraph"}] = session.log_json
  end

  test "a writer who is not the GM cannot write the section", ctx do
    stranger_token = token_for(Fixtures.user())

    assert {true, message} = write(stranger_token, "session", ctx.session.id, "prep", "Hi")
    assert message =~ "may write"
    assert text(Atlas.Campaigns.Session, ctx.session.id, :prep, ctx.gm) == ""
  end

  test "a section that the record does not have is refused", ctx do
    assert {true, message} = write(ctx.token, "session", ctx.session.id, "description", "Hi")
    assert message =~ "no such section"
  end

  test "an image that does not exist is refused", ctx do
    markdown = "![](atlas-image:#{Ecto.UUID.generate()})"
    assert {true, message} = write(ctx.token, "session", ctx.session.id, "log", markdown)
    assert message =~ "image"
  end

  test "campaign and character text follow the same rules", ctx do
    assert {false, _} = write(ctx.token, "campaign", ctx.campaign.id, "description", "A keep.")
    assert text(Atlas.Campaigns.Campaign, ctx.campaign.id, :description, ctx.gm) == "A keep."
  end

  test "notes: create, write, set visibility, rename, archive and restore", ctx do
    note =
      ok!(ctx.token, "create_note", %{input: %{campaign_id: ctx.campaign.id, title: "Plot"}})

    assert {false, _} = write(ctx.token, "note", note["id"], "body", "- a\n- b")
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

  test "sessions and campaigns: create and update details", ctx do
    created = ok!(ctx.token, "create_campaign", %{input: %{name: "New Keep"}})
    assert Ash.get!(Atlas.Campaigns.Campaign, created["id"], actor: ctx.gm).name == "New Keep"

    next = ok!(ctx.token, "create_session", %{input: %{campaign_id: ctx.campaign.id}})
    assert next["number"] == 2

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
    assert %{"body" => "I saw a ghost"} = ok!(ctx.token, "get_player_log", %{input: %{id: id}})
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
end
