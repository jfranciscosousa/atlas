defmodule Atlas.Search.ProjectionTest do
  use Atlas.DataCase, async: false

  require Ash.Query
  import Atlas.Fixtures
  import Ecto.Query

  alias Atlas.Campaigns.{Campaign, Character, Invitation, PlayerLog, Session}
  alias Atlas.Content.Note
  alias Atlas.Search.Projection

  setup do
    gm = user("projection-gm-#{Ecto.UUID.generate()}@example.com")
    player = user("projection-player-#{Ecto.UUID.generate()}@example.com")
    campaign = campaign(gm)
    invitation = Ash.create!(Invitation, %{campaign_id: campaign.id}, actor: gm)
    character = Ash.create!(Character, %{token: invitation.token}, action: :join, actor: player)
    session = Ash.create!(Session, %{campaign_id: campaign.id}, actor: gm)
    %{gm: gm, player: player, campaign: campaign, character: character, session: session}
  end

  defp search(actor, query, extra) do
    Atlas.Search.Request
    |> Ash.ActionInput.for_action(:search, Map.merge(%{query: query}, extra), actor: actor)
    |> Ash.run_action!()
  end

  defp ids(actor, query, extra \\ %{}), do: Enum.map(search(actor, query, extra).hits, & &1.id)

  defp section(id, name) do
    id = Ecto.UUID.dump!(id)

    Atlas.Repo.one!(
      from s in "search_sections",
        where: s.record_id == ^id and s.section == ^to_string(name),
        select: %{
          revision: s.revision,
          blocks: s.blocks,
          words: s.words,
          mention_keys: s.mention_keys
        }
    )
  end

  defp mention(kind, id), do: %{"type" => "mention", "props" => %{"kind" => kind, "id" => id}}
  defp text(value), do: %{"type" => "text", "text" => value, "styles" => %{}}
  defp document(content), do: [%{paragraph("") | "content" => content}]

  test "the DSL creates projections for every section and saves each revision", ctx do
    note = Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "Folios"}, actor: ctx.gm)
    log = Ash.create!(PlayerLog, %{session_id: ctx.session.id}, actor: ctx.player)

    for {resource, id, actor} <- [
          {Campaign, ctx.campaign.id, ctx.gm},
          {Character, ctx.character.id, ctx.gm},
          {Session, ctx.session.id, ctx.gm},
          {Note, note.id, ctx.gm},
          {PlayerLog, log.id, ctx.player}
        ],
        name <- Atlas.RichText.sections(resource) do
      assert %{revision: 0, blocks: []} = section(id, name)
      save_section!(resource, id, name, [paragraph("Synchronizing #{name}")], actor)
      assert %{revision: 1, words: words, blocks: [block]} = section(id, name)
      assert "synchronizing" in words
      assert "synchronizing" in block["words"]
    end
  end

  test "a player log hit names its session so that clients can open it", ctx do
    log = Ash.create!(PlayerLog, %{session_id: ctx.session.id}, actor: ctx.player)
    save_section!(PlayerLog, log.id, :body, [paragraph("Gryphons")], ctx.player)
    note = Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "Gryphons"}, actor: ctx.gm)

    hits = search(ctx.gm, "gryphons", %{}).hits
    assert %{session_id: session_id} = Enum.find(hits, &(&1.id == log.id))
    assert session_id == ctx.session.id
    assert %{session_id: nil} = Enum.find(hits, &(&1.id == note.id))
  end

  test "failed and stale saves leave the projection unchanged", ctx do
    save_section!(Session, ctx.session.id, :log, [paragraph("Sapphire")], ctx.gm)
    before = section(ctx.session.id, :log)

    assert {:error, _} =
             save_section(Session, ctx.session.id, :log, [paragraph("Obsidian")], ctx.gm,
               revision: 0
             )

    assert {:error, _} =
             save_section(Session, ctx.session.id, :log, [paragraph("Obsidian")], ctx.player)

    assert section(ctx.session.id, :log) == before
    assert ids(ctx.gm, "obsidian") == []
  end

  test "content and projections roll back together, including a failed after-action", ctx do
    changeset =
      ctx.session
      |> Ash.Changeset.for_update(
        :save_log,
        %{json: [paragraph("Rollbackword")], schema_version: 1, expected_revision: 0},
        actor: ctx.gm
      )
      |> Ash.Changeset.after_action(fn _changeset, _result ->
        assert Atlas.Repo.in_transaction?()
        {:error, "reject after projection"}
      end)

    assert {:error, _} = Ash.update(changeset)
    assert %{revision: 0, blocks: []} = section(ctx.session.id, :log)
    assert Ash.get!(Session, ctx.session.id, actor: ctx.gm).log_revision == 0
    refute "rollbackword" in Atlas.Search.Reader.matching_words(["rollbackword"])

    assert {:error, :cancelled} =
             Atlas.Repo.transaction(fn ->
               save_section!(
                 Session,
                 ctx.session.id,
                 :log,
                 [paragraph("Transactionword")],
                 ctx.gm
               )

               assert ctx.session.id in ids(ctx.gm, "transactionword")
               Atlas.Repo.rollback(:cancelled)
             end)

    assert %{revision: 0, blocks: []} = section(ctx.session.id, :log)
    assert ids(ctx.gm, "transactionword") == []
  end

  test "restoring earlier JSON replaces the searchable revision", ctx do
    original = [paragraph("Sapphire")]
    save_section!(Session, ctx.session.id, :log, original, ctx.gm)
    save_section!(Session, ctx.session.id, :log, [paragraph("Obsidian")], ctx.gm)
    save_section!(Session, ctx.session.id, :log, original, ctx.gm)
    assert %{revision: 3, words: ["sapphire"]} = section(ctx.session.id, :log)
    assert ids(ctx.gm, "obsidian") == []
    assert ids(ctx.gm, "sapphire") == [ctx.session.id]
  end

  test "mentions store references, and use current authorized labels after lifecycle changes",
       ctx do
    note =
      Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "Sapphire", visibility: :everyone},
        actor: ctx.gm
      )

    save_section!(Session, ctx.session.id, :log, document([mention("note", note.id)]), ctx.gm)
    projection = section(ctx.session.id, :log)
    assert projection.words == []
    assert projection.mention_keys == ["note:#{note.id}"]
    refute Jason.encode!(projection.blocks) =~ "Sapphire"
    refute Map.has_key?(hd(projection.blocks), "words")
    assert MapSet.new(ids(ctx.player, "sapphire")) == MapSet.new([note.id, ctx.session.id])

    note = Ash.update!(note, %{title: "Moonstone"}, action: :rename, actor: ctx.gm)
    assert ids(ctx.player, "sapphire") == []
    assert MapSet.new(ids(ctx.player, "moonstone")) == MapSet.new([note.id, ctx.session.id])
    assert section(ctx.session.id, :log) == projection

    note = Ash.update!(note, %{visibility: :only_me}, action: :set_visibility, actor: ctx.gm)
    assert ids(ctx.player, "moonstone") == []
    assert ids(ctx.player, "restricted") == [ctx.session.id]
    assert ids(ctx.gm, "moonstone", %{kinds: [:session]}) == [ctx.session.id]

    note = Ash.update!(note, %{}, action: :archive, actor: ctx.gm)
    assert ids(ctx.gm, "moonstone") == []
    assert ids(ctx.gm, "deleted") == [ctx.session.id]
    assert ids(ctx.player, "deleted") == []
    note = Ash.update!(note, %{}, action: :restore, actor: ctx.gm)
    assert MapSet.new(ids(ctx.gm, "moonstone")) == MapSet.new([note.id, ctx.session.id])
    assert ids(ctx.player, "moonstone") == []
  end

  test "current session and character names resolve without rewriting referring sections", ctx do
    save_section!(
      Campaign,
      ctx.campaign.id,
      :description,
      document([
        mention("session", ctx.session.id),
        text(" "),
        mention("character", ctx.character.id)
      ]),
      ctx.gm
    )

    Ash.update!(ctx.session, %{title: "Moonstone"}, action: :update_details, actor: ctx.gm)
    Ash.update!(ctx.character, %{name: "Sapphire"}, action: :rename, actor: ctx.player)
    assert ctx.campaign.id in ids(ctx.player, "moonstone sapphire")
    assert section(ctx.campaign.id, :description).revision == 1
  end

  test "mentions across campaigns never expose even readable target names", ctx do
    other = campaign(ctx.gm, "Elsewhere")
    note = Ash.create!(Note, %{campaign_id: other.id, title: "Moonstone"}, actor: ctx.gm)
    save_section!(Session, ctx.session.id, :log, document([mention("note", note.id)]), ctx.gm)
    assert ids(ctx.gm, "moonstone") == [note.id]
    assert ids(ctx.gm, "restricted") == [ctx.session.id]
  end

  test "a character claim changes note and mention access without reindexing", ctx do
    claimant = user("projection-claimant-#{Ecto.UUID.generate()}@example.com")

    character =
      Ash.create!(Character, %{campaign_id: ctx.campaign.id, player_label: "Future player"},
        action: :create_unclaimed,
        actor: ctx.gm
      )

    note =
      Ash.create!(
        Note,
        %{
          campaign_id: ctx.campaign.id,
          title: "Moonstone",
          visibility: :character,
          character_id: character.id
        },
        actor: ctx.gm
      )

    save_section!(Session, ctx.session.id, :log, document([mention("note", note.id)]), ctx.gm)
    before = section(ctx.session.id, :log)
    assert ids(claimant, "moonstone") == []
    Ash.create!(Character, %{token: character.claim_token}, action: :claim, actor: claimant)
    assert MapSet.new(ids(claimant, "moonstone")) == MapSet.new([note.id, ctx.session.id])
    assert section(ctx.session.id, :log) == before
  end

  test "a save from a partially selected record preserves other sections", ctx do
    save_section!(Session, ctx.session.id, :prep, [paragraph("Secretword")], ctx.gm)
    prep = section(ctx.session.id, :prep)

    record =
      Session
      |> Ash.Query.select([:id, :log_revision])
      |> Ash.Query.filter(id == ^ctx.session.id)
      |> Ash.read_one!(actor: ctx.gm)

    record
    |> Ash.Changeset.for_update(
      :save_log,
      %{json: [paragraph("Selectedword")], schema_version: 1, expected_revision: 0},
      actor: ctx.gm
    )
    |> Ash.update!()

    assert section(ctx.session.id, :prep) == prep
    assert ids(ctx.player, "selectedword") == [ctx.session.id]
  end

  test "word candidates keep no-common-trigram edits, Unicode and joined mention words", ctx do
    note =
      Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "bc", visibility: :everyone},
        actor: ctx.gm
      )

    save_section!(
      Session,
      ctx.session.id,
      :log,
      document([text("a"), mention("note", note.id), text("d")]),
      ctx.gm
    )

    assert ctx.session.id in ids(ctx.player, "abcd")
    assert ctx.session.id in ids(ctx.player, "axcd")
    save_section!(Session, ctx.session.id, :log, [paragraph("axcd abXYefgh CAFÉ Ｖａｕｌｔ")], ctx.gm)
    assert ctx.session.id in ids(ctx.gm, "abcd")
    assert ctx.session.id in ids(ctx.gm, "abcdefgh")
    assert ctx.session.id in ids(ctx.gm, "cafe vault")
    assert ctx.session.id in ids(ctx.gm, "xcd")
  end

  test "punctuation beside mentions does not require joined-word fallback", ctx do
    note =
      Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "Sapphire", visibility: :everyone},
        actor: ctx.gm
      )

    save_section!(
      Session,
      ctx.session.id,
      :log,
      document([mention("note", note.id), text(".")]),
      ctx.gm
    )

    id = Ecto.UUID.dump!(ctx.session.id)

    refute Atlas.Repo.one!(
             from s in "search_sections",
               where: s.record_id == ^id and s.section == "log",
               select: s.joined_mentions
           )

    assert ctx.session.id in ids(ctx.player, "sapphire")
    assert ids(ctx.player, "nonexistentword") == []

    save_section!(
      Session,
      ctx.session.id,
      :log,
      document([text("Ⓐ"), mention("note", note.id)]),
      ctx.gm
    )

    assert Atlas.Repo.one!(
             from s in "search_sections",
               where: s.record_id == ^id and s.section == "log",
               select: s.joined_mentions
           )

    assert ctx.session.id in ids(ctx.player, "asapphire")
  end

  test "compatibility symbols match titles and remain visible in snippets", ctx do
    note =
      Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "ℂ", visibility: :everyone},
        actor: ctx.gm
      )

    assert note.id in ids(ctx.player, "c")

    save_section!(
      Session,
      ctx.session.id,
      :log,
      [paragraph(String.duplicate("before ", 90) <> "Ⓐ")],
      ctx.gm
    )

    result = search(ctx.player, "a", %{kinds: [:session]})
    assert [%{sections: [%{blocks: [%{text: snippet}]}]}] = result.hits
    assert snippet =~ "Ⓐ"
  end

  test "hidden sections cannot affect rank, snippets or more", ctx do
    save_section!(Session, ctx.session.id, :log, [paragraph("Waterfal")], ctx.gm)

    save_section!(
      Session,
      ctx.session.id,
      :prep,
      [paragraph(String.duplicate("waterfall ", 30))],
      ctx.gm
    )

    save_section!(Character, ctx.character.id, :secret_notes, [paragraph("Waterfall")], ctx.gm)

    note =
      Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "Visible", visibility: :everyone},
        actor: ctx.gm
      )

    save_section!(Note, note.id, :body, [paragraph("Waterfall")], ctx.gm)

    assert %{hits: [%{id: id, sections: [%{section: :body}]}], more: true} =
             search(ctx.player, "waterfall", %{limit: 1})

    assert id == note.id

    assert %{hits: [%{id: id}], more: false} =
             search(ctx.player, "waterfall", %{kinds: [:session], limit: 1})

    assert id == ctx.session.id
  end

  test "creation and rename roll back title projections when a later hook fails", ctx do
    create =
      Note
      |> Ash.Changeset.for_create(
        :create,
        %{campaign_id: ctx.campaign.id, title: "Rollbacktitle"},
        actor: ctx.gm
      )
      |> Ash.Changeset.after_action(fn _changeset, _record ->
        assert Atlas.Repo.in_transaction?()
        {:error, "reject create"}
      end)

    assert {:error, _} = Ash.create(create)
    assert ids(ctx.gm, "rollbacktitle") == []
    refute "rollbacktitle" in Atlas.Search.Reader.matching_words(["rollbacktitle"])

    note =
      Ash.create!(Note, %{campaign_id: ctx.campaign.id, title: "Originaltitle"}, actor: ctx.gm)

    rename =
      note
      |> Ash.Changeset.for_update(:rename, %{title: "Rollbacktitle"}, actor: ctx.gm)
      |> Ash.Changeset.after_action(fn _changeset, _record -> {:error, "reject rename"} end)

    assert {:error, _} = Ash.update(rename, atomic_upgrade?: false)
    assert Ash.get!(Note, note.id, actor: ctx.gm).title == "Originaltitle"
    note_id = Ecto.UUID.dump!(note.id)

    assert Atlas.Repo.one!(
             from t in "search_titles", where: t.record_id == ^note_id, select: t.title
           ) == "Originaltitle"

    assert ids(ctx.gm, "originaltitle") == [note.id]
    assert ids(ctx.gm, "rollbacktitle") == []
  end

  test "backfill reloads each parent under lock after its ID scan", ctx do
    save_section!(Session, ctx.session.id, :log, [paragraph("Oldbackfill")], ctx.gm)
    handler = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach(
        handler,
        [:atlas, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == owner and
               String.starts_with?(metadata.query, ~s(SELECT s0.\"id\" FROM \"sessions\")) do
            :telemetry.detach(handler)
            save_section!(Session, ctx.session.id, :log, [paragraph("Newbackfill")], ctx.gm)
            send(owner, :saved_after_scan)
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    Projection.backfill!()
    assert_received :saved_after_scan
    assert section(ctx.session.id, :log).revision == 2
    assert ids(ctx.gm, "oldbackfill") == []
    assert ids(ctx.gm, "newbackfill") == [ctx.session.id]
  end

  test "long incompressible tokens and large vocabularies do not exceed PostgreSQL index or bind limits",
       ctx do
    long_word = for _ <- 1..7_000, into: "", do: <<Enum.random(?a..?z)>>
    vocabulary = Enum.map_join(1..14_000, " ", &"token#{&1}")

    save_section!(
      Session,
      ctx.session.id,
      :log,
      [paragraph(long_word <> " " <> vocabulary)],
      ctx.gm
    )

    id = Ecto.UUID.dump!(ctx.session.id)

    assert Atlas.Repo.one!(
             from w in "search_words",
               where: w.record_id == ^id and w.section == "log",
               select: count()
           ) == 14_001

    assert ctx.session.id in ids(ctx.gm, String.slice(long_word, 2_000, 20))
    assert ctx.session.id in ids(ctx.gm, "token13999")
  end

  test "bulk create and atomic bulk rename maintain current projections", ctx do
    result =
      Ash.bulk_create(
        [
          %{campaign_id: ctx.campaign.id, title: "Firsttitle"},
          %{campaign_id: ctx.campaign.id, title: "Secondtitle"}
        ],
        Note,
        :create,
        actor: ctx.gm,
        return_records?: true,
        return_errors?: true
      )

    assert result.status == :success
    note_ids = Enum.map(result.records, & &1.id)

    result =
      Note
      |> Ash.Query.filter(id in ^note_ids)
      |> Ash.bulk_update(:rename, %{title: "Bulkrenamed"},
        actor: ctx.gm,
        strategy: [:atomic],
        return_records?: true,
        return_errors?: true
      )

    assert result.status == :success
    stored_ids = Enum.map(note_ids, &Ecto.UUID.dump!/1)

    assert Atlas.Repo.all(
             from t in "search_titles", where: t.record_id in ^stored_ids, select: t.title
           ) == ["Bulkrenamed", "Bulkrenamed"]

    assert ids(ctx.gm, "firsttitle") == []
    assert MapSet.new(ids(ctx.gm, "bulkrenamed")) == MapSet.new(note_ids)
  end

  test "repeated joins reload locked current content rather than the manual action result", ctx do
    save_section!(
      Character,
      ctx.character.id,
      :description,
      [paragraph("Currentword")],
      ctx.player
    )

    invitation =
      Invitation
      |> Ash.Query.for_read(:active, %{campaign_id: ctx.campaign.id}, actor: ctx.gm)
      |> Ash.read_one!()

    handler = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach(
        handler,
        [:atlas, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == owner and String.contains?(metadata.query, ~s(FROM \"characters\")) and
               String.contains?(metadata.query, "ORDER BY") and
               String.contains?(metadata.query, "LIMIT") do
            :telemetry.detach(handler)

            save_section!(
              Character,
              ctx.character.id,
              :description,
              [paragraph("Newestword")],
              ctx.player
            )

            send(owner, :saved_after_manual_read)
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    again = Ash.create!(Character, %{token: invitation.token}, action: :join, actor: ctx.player)
    assert_received :saved_after_manual_read
    assert again.id == ctx.character.id
    assert section(ctx.character.id, :description).revision == 2
    assert ids(ctx.player, "currentword") == []
    assert ids(ctx.player, "newestword") == [ctx.character.id]
  end

  test "backfill restores missing projections and words from existing sections", ctx do
    save_section!(Session, ctx.session.id, :log, [paragraph("Backfillword")], ctx.gm)
    Atlas.Repo.delete_all("search_sections")
    Atlas.Repo.delete_all("search_titles")
    Atlas.Repo.delete_all("search_words")
    Projection.backfill!()
    assert section(ctx.session.id, :log).revision == 1
    assert ids(ctx.gm, "backfillword") == [ctx.session.id]
    assert ids(ctx.gm, "sunken") == [ctx.campaign.id]
  end
end
