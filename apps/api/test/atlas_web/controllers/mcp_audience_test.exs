defmodule AtlasWeb.McpAudienceTest do
  @moduledoc """
  MCP tells an agent who reads each section, so the agent does not copy a secret into text that
  more people read.

  Every tool that gives text also gives its audience. The same audience labels the section in the
  app (see `Atlas.AudienceTest`). `edit_blocks` warns when text that players read mentions a
  hidden entry. The server instructions and the tool descriptions state the rule.
  """
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.McpHelpers

  alias Atlas.Fixtures

  setup do
    gm = Fixtures.user()
    campaign = Fixtures.campaign(gm)
    {player, character} = Fixtures.join_player(campaign, gm)
    session = Ash.create!(Atlas.Campaigns.Session, %{campaign_id: campaign.id}, actor: gm)

    {:ok,
     gm: gm,
     campaign: campaign,
     player: player,
     character: character,
     session: session,
     token: token_for(gm),
     player_token: token_for(player)}
  end

  defp entry(ctx, kind, name, shown? \\ false),
    do: Fixtures.entry(ctx.gm, ctx.campaign, kind, name, %{shown: shown?})

  defp record(token, tool, id), do: ok!(token, tool, %{input: %{id: id}})

  defp read_blocks(token, kind, id, section),
    do: ok!(token, "read_blocks", %{input: %{kind: kind, id: id, section: section}})

  defp edit(token, kind, id, section, blocks) do
    call(token, "edit_blocks", %{
      input: %{
        kind: kind,
        id: id,
        section: section,
        operations: [%{op: "insert", blocks: blocks}]
      }
    })
  end

  defp saved!(result) do
    assert {false, text} = result
    Jason.decode!(text)
  end

  defp paragraph(text), do: %{type: "paragraph", content: text}

  defp mention(kind, id),
    do: %{type: "paragraph", content: [%{type: "mention", props: %{kind: kind, id: id}}]}

  defp tools(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list"})
    |> json_response(200)
    |> get_in(["result", "tools"])
    |> Map.new(&{&1["name"], &1})
  end

  defp initialize(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: "2025-06-18",
        capabilities: %{},
        clientInfo: %{name: "test", version: "1"}
      }
    })
    |> json_response(200)
    |> Map.fetch!("result")
  end

  describe "records give the audience of each section" do
    test "a world entry: the description is for the GM alone until the GM shows the entry", ctx do
      npc = entry(ctx, "npc", "Vex")

      assert %{"description_audience" => "gm_only", "secret_notes_audience" => "gm_only"} =
               record(ctx.token, "get_entry", npc.id)

      ok!(ctx.token, "set_entry_hidden", %{id: npc.id, input: %{hidden: false}})

      assert %{"description_audience" => "everyone", "secret_notes_audience" => "gm_only"} =
               record(ctx.token, "get_entry", npc.id)

      # Archiving changes no audience.
      ok!(ctx.token, "archive_entry", %{id: npc.id})
      assert %{"description_audience" => "everyone"} = record(ctx.token, "get_entry", npc.id)

      ok!(ctx.token, "set_entry_hidden", %{id: npc.id, input: %{hidden: true}})
      assert %{"description_audience" => "gm_only"} = record(ctx.token, "get_entry", npc.id)
    end

    test "a note: the body has the visibility of the note", ctx do
      %{"id" => id} =
        ok!(ctx.token, "create_note", %{input: %{campaign_id: ctx.campaign.id, title: "Plan"}})

      for visibility <- ~w(only_me me_and_gm everyone) do
        ok!(ctx.token, "set_note_visibility", %{id: id, input: %{visibility: visibility}})
        assert %{"body_audience" => ^visibility} = record(ctx.token, "get_note", id)
      end

      ok!(ctx.token, "set_note_visibility", %{
        id: id,
        input: %{visibility: "character", character_id: ctx.character.id}
      })

      assert %{"body_audience" => "character"} = record(ctx.token, "get_note", id)
    end

    test "a character, a session, a campaign and a skill", ctx do
      assert %{"description_audience" => "everyone", "secret_notes_audience" => "gm_only"} =
               record(ctx.token, "get_character", ctx.character.id)

      assert %{"log_audience" => "everyone", "prep_audience" => "gm_only"} =
               record(ctx.token, "get_session", ctx.session.id)

      assert %{
               "description_audience" => "everyone",
               "progress_rewards_audience" => "everyone"
             } = record(ctx.token, "get_campaign", ctx.campaign.id)

      %{"id" => skill} =
        ok!(ctx.token, "create_skill", %{input: %{name: "Recap", description: "When recapping."}})

      assert %{"body_audience" => "only_me"} = record(ctx.token, "get_skill", skill)
    end

    test "a player log is for every member", ctx do
      log =
        Ash.create!(Atlas.Campaigns.PlayerLog, %{session_id: ctx.session.id}, actor: ctx.player)

      assert %{"body_audience" => "everyone"} = record(ctx.token, "get_player_log", log.id)
    end

    test "get_many gives the same audience as the single tools", ctx do
      hidden = entry(ctx, "npc", "Vex")

      refs = [
        %{kind: "npc", id: hidden.id},
        %{kind: "session", id: ctx.session.id},
        %{kind: "character", id: ctx.character.id}
      ]

      assert [
               %{"record" => %{"description_audience" => "gm_only"}},
               %{"record" => %{"prep_audience" => "gm_only", "log_audience" => "everyone"}},
               %{"record" => %{"secret_notes_audience" => "gm_only"}}
             ] = ok!(ctx.token, "get_many", %{input: %{refs: refs}})["results"]
    end

    test "a player gets the audience of what the player may read, and no secret", ctx do
      npc = entry(ctx, "npc", "Vex", true)
      assert {false, _} = edit(ctx.token, "npc", npc.id, "secret_notes", [paragraph("Lich")])

      assert %{
               "description_audience" => "everyone",
               "secret_notes_audience" => "gm_only",
               "secret_notes" => nil
             } = record(ctx.player_token, "get_entry", npc.id)

      assert %{"prep_audience" => "gm_only", "prep" => nil} =
               record(ctx.player_token, "get_session", ctx.session.id)
    end
  end

  describe "read_blocks gives the audience" do
    test "of one section and of many", ctx do
      npc = entry(ctx, "npc", "Vex")

      assert %{"audience" => "gm_only"} = read_blocks(ctx.token, "npc", npc.id, "description")
      assert %{"audience" => "gm_only"} = read_blocks(ctx.token, "npc", npc.id, "secret_notes")

      assert %{"audience" => "gm_only"} =
               read_blocks(ctx.token, "session", ctx.session.id, "prep")

      assert %{"audience" => "everyone"} =
               read_blocks(ctx.token, "session", ctx.session.id, "log")

      reads = [
        %{kind: "npc", id: npc.id, section: "description"},
        %{kind: "session", id: ctx.session.id, section: "log"},
        %{kind: "session", id: ctx.session.id, section: "prep", outline: true}
      ]

      assert [
               %{"audience" => "gm_only"},
               %{"audience" => "everyone"},
               %{"audience" => "gm_only", "outline" => _}
             ] = ok!(ctx.token, "read_blocks_many", %{input: %{reads: reads}})["results"]
    end

    test "a player reads the audience of a shown entry, and nothing of a hidden one", ctx do
      hidden = entry(ctx, "npc", "Hidden")
      shown = entry(ctx, "npc", "Shown", true)

      assert %{"audience" => "everyone"} =
               read_blocks(ctx.player_token, "npc", shown.id, "description")

      assert {true, message} =
               call(ctx.player_token, "read_blocks", %{
                 input: %{kind: "npc", id: hidden.id, section: "description"}
               })

      refute message =~ "audience"
      refute message =~ "gm_only"
    end
  end

  describe "edit_blocks names who reads what you wrote" do
    test "in the result of one edit and of many", ctx do
      hidden = entry(ctx, "npc", "Vex")
      shown = entry(ctx, "npc", "Ann", true)

      assert %{"saved" => true, "audience" => "gm_only"} =
               saved!(edit(ctx.token, "npc", hidden.id, "description", [paragraph("A")]))

      assert %{"audience" => "everyone"} =
               saved!(edit(ctx.token, "npc", shown.id, "description", [paragraph("B")]))

      assert %{"audience" => "gm_only"} =
               saved!(edit(ctx.token, "session", ctx.session.id, "prep", [paragraph("C")]))

      edits = [
        %{
          kind: "npc",
          id: shown.id,
          section: "secret_notes",
          operations: [%{op: "insert", blocks: [paragraph("D")]}]
        },
        %{
          kind: "session",
          id: ctx.session.id,
          section: "log",
          operations: [%{op: "insert", blocks: [paragraph("E")]}]
        }
      ]

      assert %{"results" => [%{"audience" => "gm_only"}, %{"audience" => "everyone"}]} =
               ok!(ctx.token, "edit_blocks_many", %{input: %{edits: edits}})
    end

    test "and warns when text that players read mentions a hidden entry", ctx do
      secret = entry(ctx, "npc", "Vex")
      archived = entry(ctx, "location", "Old Keep", true)
      ok!(ctx.token, "archive_entry", %{id: archived.id})
      public = entry(ctx, "npc", "Ann", true)

      result =
        saved!(
          edit(ctx.token, "session", ctx.session.id, "log", [
            mention("npc", secret.id),
            mention("location", archived.id),
            mention("npc", public.id)
          ])
        )

      # The edit applies. The warning names the one entry that players cannot read. An archived
      # entry that is shown has the same readers as before, so it gives no warning.
      assert %{"saved" => true, "audience" => "everyone", "warnings" => [warning]} = result
      assert warning =~ ~s("Vex")
      assert warning =~ "players read this section"
      refute Enum.any?(result["warnings"], &(&1 =~ "Ann"))
      refute Enum.any?(result["warnings"], &(&1 =~ "Old Keep"))
    end

    test "and warns in a batch edit as well", ctx do
      secret = entry(ctx, "npc", "Vex")

      edits = [
        %{
          kind: "session",
          id: ctx.session.id,
          section: "log",
          operations: [%{op: "insert", blocks: [mention("npc", secret.id)]}]
        }
      ]

      assert %{"saved" => true, "results" => [%{"warnings" => [warning]}]} =
               ok!(ctx.token, "edit_blocks_many", %{input: %{edits: edits}})

      assert warning =~ ~s("Vex")
    end

    test "and does not warn when only the GM reads the text, or the mention was there already",
         ctx do
      secret = entry(ctx, "npc", "Vex")

      for {kind, id, section} <- [
            {"session", ctx.session.id, "prep"},
            {"npc", secret.id, "secret_notes"},
            {"npc", secret.id, "description"}
          ] do
        assert %{"warnings" => []} =
                 saved!(edit(ctx.token, kind, id, section, [mention("npc", secret.id)]))
      end

      # A second edit of the log adds a paragraph, and the first mention stays. Only the new
      # mention counts.
      assert %{"warnings" => [_]} =
               saved!(
                 edit(ctx.token, "session", ctx.session.id, "log", [mention("npc", secret.id)])
               )

      assert %{"warnings" => []} =
               saved!(edit(ctx.token, "session", ctx.session.id, "log", [paragraph("Later")]))
    end

    test "and tells a player nothing about a hidden entry", ctx do
      secret = entry(ctx, "npc", "Vex")

      {_error?, message} =
        edit(ctx.player_token, "character", ctx.character.id, "description", [
          mention("npc", secret.id)
        ])

      refute message =~ "Vex"
      refute message =~ "hidden"
    end
  end

  describe "search gives the audience of each matching section" do
    test "a GM sees which hits are secret", ctx do
      npc = entry(ctx, "npc", "Vex")
      assert {false, _} = edit(ctx.token, "npc", npc.id, "description", [paragraph("A lich")])

      assert {false, _} =
               edit(ctx.token, "npc", npc.id, "secret_notes", [paragraph("A lich too")])

      assert {false, _} = edit(ctx.token, "session", ctx.session.id, "log", [paragraph("A lich")])

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "prep", [paragraph("A lich")])

      %{"hits" => hits} =
        ok!(ctx.token, "search", %{input: %{campaign_id: ctx.campaign.id, query: "lich"}})

      audiences = fn kind ->
        hits
        |> Enum.find(&(&1["kind"] == kind))
        |> Map.fetch!("sections")
        |> Map.new(&{&1["section"], &1["audience"]})
      end

      assert %{"description" => "gm_only", "secret_notes" => "gm_only"} = audiences.("npc")
      assert %{"log" => "everyone", "prep" => "gm_only"} = audiences.("session")

      ok!(ctx.token, "set_entry_hidden", %{id: npc.id, input: %{hidden: false}})

      %{"hits" => hits} =
        ok!(ctx.token, "search", %{input: %{campaign_id: ctx.campaign.id, query: "lich"}})

      npc_hit = Enum.find(hits, &(&1["kind"] == "npc"))

      assert %{"audience" => "everyone"} =
               Enum.find(npc_hit["sections"], &(&1["section"] == "description"))
    end

    test "a player finds no secret section", ctx do
      npc = entry(ctx, "npc", "Vex", true)
      assert {false, _} = edit(ctx.token, "npc", npc.id, "secret_notes", [paragraph("A lich")])

      assert {false, _} =
               edit(ctx.token, "session", ctx.session.id, "prep", [paragraph("A lich")])

      %{"hits" => hits} =
        ok!(ctx.player_token, "search", %{input: %{campaign_id: ctx.campaign.id, query: "lich"}})

      assert hits == []
    end
  end

  describe "the rule is in front of the agent" do
    test "the server instructions keep the order to call list_skills first, and state the rule",
         ctx do
      %{"instructions" => instructions} = initialize(ctx.token)

      assert instructions |> String.split("\n", parts: 2) |> hd() =~ "call list_skills"
      assert instructions =~ "Every section has an audience"
      assert instructions =~ "Never copy, quote, summarize or hint"

      for {audience, label} <- Atlas.Audience.labels() do
        assert instructions =~ "#{audience} (#{label})"
      end
    end

    test "every tool that gives text names the audience", ctx do
      tools = tools(ctx.token)

      for name <-
            ~w(get_entry get_note get_session get_character get_campaign get_player_log get_many
               read_blocks read_blocks_many search) do
        assert tools[name]["description"] =~ "audience", "#{name} does not name the audience"
      end

      for name <- ~w(edit_blocks edit_blocks_many) do
        assert tools[name]["description"] =~ "audience", "#{name} does not name the audience"
      end
    end

    test "the tools that publish text warn before they do", ctx do
      tools = tools(ctx.token)

      for name <- ~w(set_entry_hidden set_entries_hidden) do
        assert tools[name]["description"] =~ "publishes its description to every player"
      end

      assert tools["set_note_visibility"]["description"] =~ "publishes the body"
      assert tools["create_entry"]["description"] =~ "Put every secret in the secret notes"
    end
  end
end
