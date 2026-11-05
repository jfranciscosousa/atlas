defmodule AtlasWeb.McpBatchTest do
  @moduledoc """
  The MCP tools that read or change many records in one call: `get_many`, `read_blocks_many`,
  `edit_blocks_many`, `set_entries_hidden`, `archive_entries` and `restore_entries`.

  Reads give one result for each ref, and a player sees the same as through the single tools.
  Writes succeed or fail as a whole.
  """
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.McpHelpers

  alias Atlas.Fixtures
  alias Atlas.RichText.Collab

  @not_found "is not a record that exists and that you may read"

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

  defp note(ctx, title, visibility \\ "everyone") do
    %{"id" => id} =
      ok!(ctx.token, "create_note", %{input: %{campaign_id: ctx.campaign.id, title: title}})

    ok!(ctx.token, "set_note_visibility", %{id: id, input: %{visibility: visibility}})
    id
  end

  defp paragraph(text), do: %{type: "paragraph", content: text}

  defp insert_op(text), do: %{op: "insert", blocks: [paragraph(text)]}

  defp edit_item(kind, id, section, text, extra \\ %{}) do
    Map.merge(
      %{kind: kind, id: id, section: section, operations: [insert_op(text)]},
      extra
    )
  end

  defp get_many(token, refs), do: ok!(token, "get_many", %{input: %{refs: refs}})["results"]

  defp edit_many(token, edits), do: call(token, "edit_blocks_many", %{input: %{edits: edits}})

  defp tool_names(token), do: token |> tools() |> Enum.map(& &1["name"])
  defp tool(token, name), do: token |> tools() |> Enum.find(&(&1["name"] == name))

  defp tools(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list"})
    |> json_response(200)
    |> get_in(["result", "tools"])
  end

  defp section_json(resource, id, section, actor) do
    resource |> Ash.get!(id, actor: actor) |> Map.fetch!(Atlas.RichText.json_attribute(section))
  end

  defp revision(resource, id, section, actor) do
    resource
    |> Ash.get!(id, actor: actor)
    |> Map.fetch!(Atlas.RichText.revision_attribute(section))
  end

  describe "get_many" do
    test "gives each record as its single get_* tool gives it", ctx do
      npc = entry(ctx, "npc", "Vex", true)
      note_id = note(ctx, "Plan")

      refs = [
        %{kind: "npc", id: npc.id},
        %{kind: "note", id: note_id},
        %{kind: "session", id: ctx.session.id},
        %{kind: "character", id: ctx.character.id},
        %{kind: "campaign", id: ctx.campaign.id}
      ]

      expected = [
        ok!(ctx.token, "get_entry", %{input: %{id: npc.id}}),
        ok!(ctx.token, "get_note", %{input: %{id: note_id}}),
        ok!(ctx.token, "get_session", %{input: %{id: ctx.session.id}}),
        ok!(ctx.token, "get_character", %{input: %{id: ctx.character.id}}),
        ok!(ctx.token, "get_campaign", %{input: %{id: ctx.campaign.id}})
      ]

      results = get_many(ctx.token, refs)

      assert Enum.map(results, & &1["record"]) == expected
      assert Enum.map(results, & &1["kind"]) == ~w(npc note session character campaign)
    end

    test "one failed read does not stop the others", ctx do
      npc = entry(ctx, "npc", "Vex", true)

      assert [
               %{"id" => id, "record" => %{"name" => "Vex"}},
               %{"error" => @not_found} = missing
             ] =
               get_many(ctx.token, [
                 %{kind: "npc", id: npc.id},
                 %{kind: "npc", id: Ash.UUID.generate()}
               ])

      assert id == npc.id
      refute Map.has_key?(missing, "record")
    end

    test "an entry opens only under its own kind", ctx do
      npc = entry(ctx, "npc", "Vex", true)

      assert [%{"error" => @not_found}] = get_many(ctx.token, [%{kind: "location", id: npc.id}])
    end

    test "refuses an empty list and more than 50 refs", ctx do
      assert {true, _} = call(ctx.token, "get_many", %{input: %{refs: []}})

      refs = for _ <- 1..51, do: %{kind: "npc", id: Ash.UUID.generate()}
      assert {true, _} = call(ctx.token, "get_many", %{input: %{refs: refs}})

      refs = for _ <- 1..50, do: %{kind: "npc", id: Ash.UUID.generate()}
      assert 50 == length(get_many(ctx.token, refs))
    end

    test "a player gets the same as the single tools, and never a hidden record", ctx do
      hidden = entry(ctx, "npc", "Hidden one")
      shown = entry(ctx, "npc", "Shown one", true)
      archived = entry(ctx, "npc", "Gone one", true)
      ok!(ctx.token, "archive_entry", %{id: archived.id})
      private = note(ctx, "Private plan", "me_and_gm")
      public = note(ctx, "Public plan")

      %{"id" => skill} =
        ok!(ctx.token, "create_skill", %{input: %{name: "Recap", description: "When recapping."}})

      refs = [
        %{kind: "npc", id: hidden.id},
        %{kind: "npc", id: shown.id},
        %{kind: "npc", id: archived.id},
        %{kind: "note", id: private},
        %{kind: "note", id: public},
        %{kind: "skill", id: skill},
        %{kind: "npc", id: Ash.UUID.generate()}
      ]

      assert [hidden_r, shown_r, archived_r, private_r, public_r, skill_r, missing_r] =
               get_many(ctx.player_token, refs)

      # Hidden, private, other people's and missing records give the same answer.
      for result <- [hidden_r, private_r, skill_r, missing_r] do
        assert %{"error" => @not_found} = Map.take(result, ["error"])
        refute Map.has_key?(result, "record")
      end

      assert shown_r["record"] ==
               ok!(ctx.player_token, "get_entry", %{input: %{id: shown.id}})

      assert %{"secret_notes" => nil, "secret_notes_revision" => nil} = shown_r["record"]

      # An archived entry that is shown keeps its readers.
      assert archived_r["record"] ==
               ok!(ctx.player_token, "get_entry", %{input: %{id: archived.id}})

      assert public_r["record"] ==
               ok!(ctx.player_token, "get_note", %{input: %{id: public}})
    end

    test "a player of another campaign reads nothing", ctx do
      npc = entry(ctx, "npc", "Vex", true)
      stranger = token_for(Fixtures.user())

      assert [%{"error" => @not_found}, %{"error" => @not_found}] =
               get_many(stranger, [
                 %{kind: "npc", id: npc.id},
                 %{kind: "campaign", id: ctx.campaign.id}
               ])
    end

    test "a mention has the label that the reader may see", ctx do
      vex = entry(ctx, "npc", "Vex")
      plan = note(ctx, "Plan")

      assert {false, _} =
               call(ctx.token, "edit_blocks", %{
                 input: %{
                   kind: "note",
                   id: plan,
                   section: "body",
                   operations: [
                     %{
                       op: "insert",
                       blocks: [
                         %{
                           type: "paragraph",
                           content: [%{type: "mention", props: %{kind: "npc", id: vex.id}}]
                         }
                       ]
                     }
                   ]
                 }
               })

      label = fn token ->
        [%{"record" => %{"body" => [%{"content" => [%{"props" => %{"label" => label}}]}]}}] =
          get_many(token, [%{kind: "note", id: plan}])

        label
      end

      assert "Vex" == label.(ctx.token)
      assert "Restricted entry" == label.(ctx.player_token)
    end
  end

  describe "read_blocks_many" do
    test "gives the blocks of each section, and an error for one that fails", ctx do
      npc = entry(ctx, "npc", "Vex", true)
      assert {false, _} = edit_many(ctx.token, [edit_item("npc", npc.id, "description", "Text")])

      reads = [
        %{kind: "npc", id: npc.id, section: "description"},
        %{kind: "npc", id: npc.id, section: "secret_notes", outline: true},
        %{kind: "npc", id: Ash.UUID.generate(), section: "description"}
      ]

      assert [one, two, three] =
               ok!(ctx.token, "read_blocks_many", %{input: %{reads: reads}})["results"]

      assert one ==
               Map.merge(
                 %{"kind" => "npc", "id" => npc.id, "section" => "description"},
                 ok!(ctx.token, "read_blocks", %{
                   input: %{kind: "npc", id: npc.id, section: "description"}
                 })
               )

      assert %{"outline" => [], "revision" => 0} = two
      assert %{"error" => "is not a section that exists and that you may read"} = three
    end

    test "a player reads what read_blocks gives, and nothing of a hidden entry", ctx do
      hidden = entry(ctx, "npc", "Hidden")
      shown = entry(ctx, "npc", "Shown", true)
      assert {false, _} = edit_many(ctx.token, [edit_item("npc", shown.id, "description", "Hi")])
      assert {false, _} = edit_many(ctx.token, [edit_item("npc", shown.id, "secret_notes", "No")])

      reads = [
        %{kind: "npc", id: hidden.id, section: "description"},
        %{kind: "npc", id: shown.id, section: "description"},
        %{kind: "npc", id: shown.id, section: "secret_notes"}
      ]

      assert [hidden_r, shown_r, secret_r] =
               ok!(ctx.player_token, "read_blocks_many", %{input: %{reads: reads}})["results"]

      assert %{"error" => _} = hidden_r
      refute Map.has_key?(hidden_r, "blocks")

      single =
        ok!(ctx.player_token, "read_blocks", %{
          input: %{kind: "npc", id: shown.id, section: "description"}
        })

      assert Map.drop(shown_r, ["kind", "id", "section"]) == single

      # The single tool refuses the secret notes of a player too, with the same reason.
      assert {true, refusal} =
               call(ctx.player_token, "read_blocks", %{
                 input: %{kind: "npc", id: shown.id, section: "secret_notes"}
               })

      assert %{"error" => error} = secret_r
      assert refusal =~ error
      refute Map.has_key?(secret_r, "blocks")
    end

    test "refuses more than 50 reads", ctx do
      reads = for _ <- 1..51, do: %{kind: "npc", id: Ash.UUID.generate(), section: "description"}
      assert {true, _} = call(ctx.token, "read_blocks_many", %{input: %{reads: reads}})
    end
  end

  describe "edit_blocks_many" do
    test "edits sections of several records in one call", ctx do
      npc = entry(ctx, "npc", "Vex")
      note_id = note(ctx, "Plan")

      edits = [
        edit_item("npc", npc.id, "description", "Who Vex is"),
        edit_item("npc", npc.id, "secret_notes", "What Vex hides"),
        edit_item("note", note_id, "body", "The plan"),
        edit_item("session", ctx.session.id, "prep", "The prep")
      ]

      assert {false, text} = edit_many(ctx.token, edits)

      assert %{"saved" => true, "results" => [one, two, three, four]} = Jason.decode!(text)

      assert %{"kind" => "npc", "section" => "description", "saved" => true, "revision" => 1} =
               one

      assert %{"section" => "secret_notes", "inserted" => [_]} = two
      assert %{"kind" => "note", "id" => ^note_id} = three
      assert %{"kind" => "session", "section" => "prep"} = four

      assert [%{"content" => [%{"text" => "Who Vex is"}]}] =
               section_json(Atlas.Content.Entry, npc.id, :description, ctx.gm)

      assert [%{"content" => [%{"text" => "What Vex hides"}]}] =
               section_json(Atlas.Content.Entry, npc.id, :secret_notes, ctx.gm)

      assert [%{"content" => [%{"text" => "The plan"}]}] =
               section_json(Atlas.Content.Note, note_id, :body, ctx.gm)

      assert 1 == revision(Atlas.Campaigns.Session, ctx.session.id, :prep, ctx.gm)
    end

    test "open editors receive the updates after the edits are stored", ctx do
      npc = entry(ctx, "npc", "Vex")
      {:ok, one} = Collab.parse("npc:#{npc.id}:description")
      {:ok, two} = Collab.parse("session:#{ctx.session.id}:prep")
      Phoenix.PubSub.subscribe(Atlas.PubSub, Collab.topic(one))
      Phoenix.PubSub.subscribe(Atlas.PubSub, Collab.topic(two))

      assert {false, _} =
               edit_many(ctx.token, [
                 edit_item("npc", npc.id, "description", "A"),
                 edit_item("session", ctx.session.id, "prep", "B")
               ])

      assert_receive {:collab_update, first} when is_binary(first)
      assert_receive {:collab_update, second} when is_binary(second)
    end

    test "an edit that cannot be planned changes nothing and names its index", ctx do
      npc = entry(ctx, "npc", "Vex")

      edits = [
        edit_item("npc", npc.id, "description", "Fine"),
        %{
          kind: "npc",
          id: npc.id,
          section: "secret_notes",
          operations: [%{op: "insert", blocks: [%{type: "nonsense", content: "x"}]}]
        }
      ]

      assert {true, message} = edit_many(ctx.token, edits)
      assert message =~ "edits[1]"
      assert message =~ "Nothing was changed"

      assert [] = section_json(Atlas.Content.Entry, npc.id, :description, ctx.gm)
      assert 0 == revision(Atlas.Content.Entry, npc.id, :description, ctx.gm)
    end

    test "an edit that fails when it is stored undoes the edits stored before it", ctx do
      npc = entry(ctx, "npc", "Vex")
      note_id = note(ctx, "Plan")
      {:ok, target} = Collab.parse("npc:#{npc.id}:description")
      Phoenix.PubSub.subscribe(Atlas.PubSub, Collab.topic(target))

      # The npc edit sorts before the note edit, so it is stored first.
      edits = [
        edit_item("npc", npc.id, "description", "Fine"),
        edit_item("note", note_id, "body", "Stale", %{expected_revision: 7})
      ]

      assert {true, message} = edit_many(ctx.token, edits)
      assert message =~ "edits[1]"
      assert message =~ "changed since you read it"
      assert message =~ "Nothing was changed"

      assert [] = section_json(Atlas.Content.Entry, npc.id, :description, ctx.gm)
      assert 0 == revision(Atlas.Content.Entry, npc.id, :description, ctx.gm)
      assert [] = section_json(Atlas.Content.Note, note_id, :body, ctx.gm)

      # The editors hear nothing of an edit that was undone, and the section still takes edits.
      refute_received {:collab_update, _}
      assert {false, _} = edit_many(ctx.token, [edit_item("npc", npc.id, "description", "Again")])
      assert 1 == revision(Atlas.Content.Entry, npc.id, :description, ctx.gm)
    end

    test "a section the writer may not write undoes all edits", ctx do
      npc = entry(ctx, "npc", "Vex", true)
      public = note(ctx, "Public plan")

      edits = [
        edit_item("note", public, "body", "A player may write this"),
        edit_item("npc", npc.id, "description", "A player may not write this")
      ]

      assert {true, message} = edit_many(ctx.player_token, edits)
      assert message =~ "edits[1]"
      assert message =~ "may write"
      assert [] = section_json(Atlas.Content.Note, public, :body, ctx.gm)
      assert [] = section_json(Atlas.Content.Entry, npc.id, :description, ctx.gm)
    end

    test "a player cannot reach a hidden entry", ctx do
      hidden = entry(ctx, "npc", "Hidden")

      assert {true, message} =
               edit_many(ctx.player_token, [edit_item("npc", hidden.id, "description", "x")])

      assert message =~ "may write"
      refute message =~ "Hidden"
      assert [] = section_json(Atlas.Content.Entry, hidden.id, :description, ctx.gm)
    end

    test "the guards of edit_blocks apply to each edit", ctx do
      npc = entry(ctx, "npc", "Vex")
      assert {false, _} = edit_many(ctx.token, [edit_item("npc", npc.id, "description", "Keep")])

      many =
        Enum.map(1..12, fn n -> insert_op("Line #{n}") end)

      assert {false, _} =
               edit_many(ctx.token, [
                 %{kind: "npc", id: npc.id, section: "secret_notes", operations: many}
               ])

      ids =
        section_json(Atlas.Content.Entry, npc.id, :secret_notes, ctx.gm) |> Enum.map(& &1["id"])

      deletes = Enum.map(ids, &%{op: "delete", id: &1})

      assert {true, message} =
               edit_many(ctx.token, [
                 edit_item("npc", npc.id, "description", "Other"),
                 %{kind: "npc", id: npc.id, section: "secret_notes", operations: deletes}
               ])

      assert message =~ "edits[1]"
      assert message =~ "delete_many"
      assert 12 == length(section_json(Atlas.Content.Entry, npc.id, :secret_notes, ctx.gm))
    end

    test "warnings come back for each edit", ctx do
      npc = entry(ctx, "npc", "Vex")
      assert {false, _} = edit_many(ctx.token, [edit_item("npc", npc.id, "description", "Old")])
      [%{"id" => block}] = section_json(Atlas.Content.Entry, npc.id, :description, ctx.gm)

      update = %{op: "update", id: block, content: "New"}

      assert {false, text} =
               edit_many(ctx.token, [
                 %{kind: "npc", id: npc.id, section: "description", operations: [update]}
               ])

      assert %{"results" => [%{"warnings" => [warning]}]} = Jason.decode!(text)
      assert warning =~ "had no hash"
    end

    test "refuses two edits of one section", ctx do
      npc = entry(ctx, "npc", "Vex")

      assert {true, message} =
               edit_many(ctx.token, [
                 edit_item("npc", npc.id, "description", "One"),
                 edit_item("npc", npc.id, "description", "Two")
               ])

      assert message =~ "twice"
      assert [] = section_json(Atlas.Content.Entry, npc.id, :description, ctx.gm)
    end

    test "refuses more than 50 edits and more than 500 operations", ctx do
      npc = entry(ctx, "npc", "Vex")
      one = edit_item("npc", npc.id, "description", "x")
      assert {true, _} = edit_many(ctx.token, List.duplicate(one, 51))
      assert {true, _} = edit_many(ctx.token, [])

      operations = List.duplicate(insert_op("x"), 100)
      big = %{kind: "npc", id: npc.id, section: "description", operations: operations}
      other = %{big | section: "secret_notes"}
      session = %{big | kind: "session", id: ctx.session.id, section: "prep"}

      edits = [big, other, session, %{session | section: "log"}, %{big | kind: "location"}]
      edits = edits ++ [%{big | kind: "faction"}]

      assert {true, message} = edit_many(ctx.token, edits)
      assert message =~ "operations in total"
    end
  end

  describe "bulk changes of entries" do
    defp ids(entries), do: Enum.map(entries, & &1.id)

    defp bulk(token, tool, ids, extra \\ %{}),
      do: call(token, tool, %{input: Map.merge(%{ids: ids}, extra)})

    defp hidden?(ctx, entry),
      do: Ash.get!(Atlas.Content.Entry, entry.id, actor: ctx.gm).hidden

    defp archived?(ctx, entry),
      do: Ash.get!(Atlas.Content.Entry, entry.id, actor: ctx.gm).archived_at != nil

    test "set_entries_hidden shows and hides many entries, in the order of ids", ctx do
      entries = [entry(ctx, "npc", "A"), entry(ctx, "item", "B"), entry(ctx, "plot", "C")]
      reversed = entries |> ids() |> Enum.reverse()

      assert {false, text} = bulk(ctx.token, "set_entries_hidden", reversed, %{hidden: false})

      assert %{"entries" => results} = Jason.decode!(text)
      assert Enum.map(results, & &1["id"]) == reversed
      assert Enum.all?(results, &(&1["hidden"] == false))
      assert Enum.all?(entries, &(not hidden?(ctx, &1)))

      assert {false, _} = bulk(ctx.token, "set_entries_hidden", ids(entries), %{hidden: true})
      assert Enum.all?(entries, &hidden?(ctx, &1))
    end

    test "archive_entries and restore_entries move many entries", ctx do
      entries = [entry(ctx, "npc", "A"), entry(ctx, "location", "B")]

      assert {false, text} = bulk(ctx.token, "archive_entries", ids(entries))
      assert %{"entries" => [%{"archived_at" => at}, _]} = Jason.decode!(text)
      assert at
      assert Enum.all?(entries, &archived?(ctx, &1))

      assert {false, text} = bulk(ctx.token, "restore_entries", ids(entries))
      assert %{"entries" => [%{"archived_at" => nil}, _]} = Jason.decode!(text)
      assert Enum.all?(entries, &(not archived?(ctx, &1)))
    end

    test "one id that fails changes no entry", ctx do
      entries = [entry(ctx, "npc", "A"), entry(ctx, "npc", "B")]
      missing = Ash.UUID.generate()

      for {tool, extra} <- [
            {"set_entries_hidden", %{hidden: false}},
            {"archive_entries", %{}},
            {"restore_entries", %{}}
          ] do
        assert {true, message} = bulk(ctx.token, tool, ids(entries) ++ [missing], extra), tool
        assert message =~ "ids[2]"
        assert message =~ "Nothing was changed"
      end

      assert Enum.all?(entries, &(hidden?(ctx, &1) and not archived?(ctx, &1)))
    end

    test "an entry of a campaign the writer does not run undoes all changes", ctx do
      mine = entry(ctx, "npc", "Mine")
      other_gm = Fixtures.user()
      other = Fixtures.entry(other_gm, Fixtures.campaign(other_gm, "Other"), "npc", "Theirs")

      assert {true, message} =
               bulk(ctx.token, "set_entries_hidden", [mine.id, other.id], %{hidden: false})

      assert message =~ "ids[1]"
      assert hidden?(ctx, mine)
      assert Ash.get!(Atlas.Content.Entry, other.id, actor: other_gm).hidden
    end

    test "a player changes nothing, and cannot tell a hidden entry from a missing one", ctx do
      hidden = entry(ctx, "npc", "Hidden")
      shown = entry(ctx, "npc", "Shown", true)

      for {tool, extra} <- [
            {"set_entries_hidden", %{hidden: true}},
            {"archive_entries", %{}},
            {"restore_entries", %{}}
          ] do
        assert {true, for_hidden} = bulk(ctx.player_token, tool, [hidden.id], extra)
        assert {true, for_missing} = bulk(ctx.player_token, tool, [Ash.UUID.generate()], extra)
        assert for_hidden == for_missing

        assert {true, _} = bulk(ctx.player_token, tool, [shown.id], extra)
      end

      refute hidden?(ctx, shown)
      refute archived?(ctx, shown)
      refute Enum.any?([hidden, shown], &archived?(ctx, &1))
    end

    test "refuses an empty list and more than 50 ids", ctx do
      assert {true, _} = bulk(ctx.token, "archive_entries", [])

      assert {true, _} =
               bulk(ctx.token, "archive_entries", for(_ <- 1..51, do: Ash.UUID.generate()))
    end

    test "the same id twice changes the entry once", ctx do
      entry = entry(ctx, "npc", "A")

      assert {false, text} =
               bulk(ctx.token, "set_entries_hidden", [entry.id, entry.id], %{hidden: false})

      assert %{"entries" => [_]} = Jason.decode!(text)
    end
  end

  describe "queries" do
    @repo_query [:atlas, :repo, :query]

    # Counts the queries that the test process runs while `fun` runs.
    defp count_queries(fun) do
      ref = make_ref()
      id = {__MODULE__, ref}
      :telemetry.attach(id, @repo_query, &__MODULE__.handle_query/4, %{pid: self(), ref: ref})

      try do
        fun.()
        count_messages(ref, 0)
      after
        :telemetry.detach(id)
      end
    end

    def handle_query(_event, _measurements, _metadata, %{pid: pid, ref: ref}) do
      if self() == pid, do: send(pid, {ref, :query})
    end

    defp count_messages(ref, count) do
      receive do
        {^ref, :query} -> count_messages(ref, count + 1)
      after
        0 -> count
      end
    end

    # The queries of a call must not grow with the number of items: 50 items cost about as many
    # queries as 5. `per_item` is the growth that one more item may cost.
    defp assert_flat(ctx, label, per_item, call) do
      few = count_queries(fn -> call.(Enum.take(ctx.entries, 5)) end)
      many = count_queries(fn -> call.(ctx.entries) end)

      assert many - few <= per_item * 45,
             "#{label}: #{few} queries for 5 items, #{many} for 50 (at most #{per_item} more for each item)"
    end

    setup ctx do
      mention = %{type: "mention", props: %{kind: "npc", id: entry(ctx, "npc", "Named", true).id}}

      entries =
        for n <- 1..50 do
          entry = entry(ctx, "npc", "Entry #{n}", true)

          assert {false, _} =
                   edit_many(ctx.token, [
                     %{
                       kind: "npc",
                       id: entry.id,
                       section: "description",
                       operations: [
                         %{op: "insert", blocks: [%{type: "paragraph", content: [mention]}]}
                       ]
                     }
                   ])

          entry
        end

      {:ok, entries: entries}
    end

    test "get_many does not query for each record", ctx do
      assert_flat(ctx, "get_many", 0, fn entries ->
        refs = Enum.map(entries, &%{kind: "npc", id: &1.id})
        assert length(get_many(ctx.player_token, refs)) == length(entries)
      end)
    end

    test "read_blocks_many does not query for each section", ctx do
      assert_flat(ctx, "read_blocks_many", 0, fn entries ->
        reads = Enum.map(entries, &%{kind: "npc", id: &1.id, section: "description"})

        assert %{"results" => results} =
                 ok!(ctx.player_token, "read_blocks_many", %{input: %{reads: reads}})

        assert Enum.all?(results, &Map.has_key?(&1, "blocks"))
      end)
    end

    test "the bulk entry tools do not query for each entry", ctx do
      for {tool, extra} <- [
            {"set_entries_hidden", %{hidden: true}},
            {"archive_entries", %{}},
            {"restore_entries", %{}}
          ] do
        assert_flat(ctx, tool, 0, fn entries ->
          assert {false, _} = bulk(ctx.token, tool, ids(entries), extra)
        end)
      end
    end

    test "edit_blocks_many reads once for all sections, and writes once for each", ctx do
      # Reads and locks are shared. Each edit still writes its own section, which takes about nine
      # statements: the update of the record and its row lock, the search index (three), the
      # stored document, and the policy checks of the save. The guard catches a read that returns
      # to a query for each section.
      assert_flat(ctx, "edit_blocks_many", 10, fn entries ->
        edits = Enum.map(entries, &edit_item("npc", &1.id, "description", "Changed"))
        assert {false, _} = edit_many(ctx.token, edits)
      end)
    end

    test "a save that Atlas rejects fails the batch and changes nothing", ctx do
      %{"id" => skill} =
        ok!(ctx.token, "create_skill", %{input: %{name: "Recap", description: "When recapping."}})

      mention = %{type: "mention", props: %{kind: "npc", id: hd(ctx.entries).id}}
      note_id = note(ctx, "Plan")

      edits = [
        edit_item("note", note_id, "body", "Fine"),
        %{
          kind: "skill",
          id: skill,
          section: "body",
          operations: [
            %{op: "insert", blocks: [%{type: "paragraph", content: [mention]}]}
          ]
        }
      ]

      assert {true, message} = edit_many(ctx.token, edits)
      assert message =~ "edits[1]"
      assert message =~ "mention"
      assert [] = section_json(Atlas.Content.Note, note_id, :body, ctx.gm)
    end
  end

  test "the tools are listed with the limit in their description", ctx do
    names = tool_names(ctx.token)

    for name <-
          ~w(get_many read_blocks_many edit_blocks_many set_entries_hidden archive_entries restore_entries) do
      assert name in names
    end

    for name <- ~w(get_many read_blocks_many edit_blocks_many) do
      assert %{"description" => description} = tool(ctx.token, name)
      assert String.replace(description, ~r/\s+/, " ") =~ "at most 50"
    end
  end
end
