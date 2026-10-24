defmodule Atlas.Search.Projection do
  @moduledoc false

  alias Atlas.RichText.{Document, PlainText}
  alias Atlas.Search.Match
  import Ecto.Query

  @resources [
    {:campaign, Atlas.Campaigns.Campaign},
    {:session, Atlas.Campaigns.Session},
    {:character, Atlas.Campaigns.Character},
    {:note, Atlas.Content.Note},
    {:player_log, Atlas.Campaigns.PlayerLog}
  ]

  def resources, do: @resources

  # Read the stored row, not the action result: field policies can redact the result, and a
  # caller can supply a partially selected or stale record. The parent write holds its row lock.
  def sync!(resource, id, sections) do
    {kind, ^resource} = Enum.find(@resources, &(elem(&1, 1) == resource))
    table = AshPostgres.DataLayer.Info.table(resource)

    attributes =
      Enum.flat_map(
        sections,
        &[Atlas.RichText.json_attribute(&1), Atlas.RichText.revision_attribute(&1)]
      )

    row =
      Atlas.Repo.one!(
        from r in table,
          where: r.id == type(^id, Ecto.UUID),
          lock: "FOR UPDATE",
          select: map(r, ^attributes)
      )

    Enum.each(sections, fn section ->
      put!(
        kind,
        id,
        section,
        Map.fetch!(row, Atlas.RichText.json_attribute(section)),
        Map.fetch!(row, Atlas.RichText.revision_attribute(section))
      )
    end)
  end

  def put!(kind, id, section, document, revision) do
    blocks = blocks(document)

    words =
      blocks
      |> Enum.flat_map(fn block ->
        Enum.flat_map(block["parts"], fn
          %{"text" => text} -> Match.terms(text)
          _ -> []
        end)
      end)
      |> Enum.uniq()

    put_words!(kind, id, to_string(section), words)

    mention_keys =
      for block <- blocks,
          %{"kind" => kind, "id" => id} <- block["parts"],
          uniq: true,
          do: kind <> ":" <> id

    Atlas.Repo.insert_all(
      "search_sections",
      [
        %{
          kind: to_string(kind),
          record_id: Ecto.UUID.dump!(id),
          section: to_string(section),
          revision: revision,
          blocks: blocks,
          words: Enum.filter(words, &(byte_size(&1) <= 1_000)),
          has_long_words: Enum.any?(words, &(byte_size(&1) > 1_000)),
          has_mentions: mention_keys != [],
          mention_keys: mention_keys,
          joined_mentions: Enum.any?(blocks, &joined_mentions?(&1["parts"]))
        }
      ],
      conflict_target: [:kind, :record_id, :section],
      on_conflict:
        {:replace,
         [
           :revision,
           :blocks,
           :words,
           :has_long_words,
           :has_mentions,
           :mention_keys,
           :joined_mentions
         ]}
    )
  end

  defp blocks(document) do
    refs = Document.mention_refs(document) |> Enum.uniq()
    marker = marker(document)

    labels =
      refs
      |> Enum.with_index()
      |> Map.new(fn {ref, index} -> {ref, marker <> to_string(index) <> marker} end)

    tokens = Map.new(labels, fn {{kind, id}, token} -> {token, %{"kind" => kind, "id" => id}} end)
    pattern = Regex.compile!(Regex.escape(marker) <> "[0-9]+" <> Regex.escape(marker))

    document
    |> PlainText.flat(labels: labels, links: false, at: false, images: true)
    |> Enum.map(fn block ->
      parts =
        Regex.split(pattern, block.text, include_captures: true, trim: true)
        |> Enum.map(&Map.get(tokens, &1, %{"text" => &1}))

      projection = %{"id" => block.id, "parts" => parts}

      if Enum.any?(parts, &Map.has_key?(&1, "kind")) do
        literal_words =
          Enum.flat_map(parts, fn
            %{"text" => text} -> Match.terms(text)
            _ -> []
          end)

        Map.merge(projection, %{
          "literal_words" => Enum.uniq(literal_words),
          "joined_mentions" => joined_mentions?(parts)
        })
      else
        Map.put(projection, "words", Match.terms(block.text))
      end
    end)
  end

  defp joined_mentions?(parts) do
    parts
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn
      [%{"kind" => _}, %{"kind" => _}] ->
        true

      [%{"text" => text}, %{"kind" => _}] ->
        String.match?(String.normalize(text, :nfkd), ~r/[\p{L}\p{N}\p{M}]$/u)

      [%{"kind" => _}, %{"text" => text}] ->
        String.match?(String.normalize(text, :nfkd), ~r/^[\p{L}\p{N}\p{M}]/u)

      _ ->
        false
    end)
  end

  defp put_words!(kind, id, section, words) do
    kind = to_string(kind)
    id = Ecto.UUID.dump!(id)

    Atlas.Repo.delete_all(
      from w in "search_words",
        where: w.kind == ^kind and w.record_id == ^id and w.section == ^section
    )

    words
    |> Enum.with_index()
    |> Enum.chunk_every(2_000)
    |> Enum.each(fn chunk ->
      Atlas.Repo.insert_all(
        "search_words",
        Enum.map(chunk, fn {word, ordinal} ->
          %{
            kind: kind,
            record_id: id,
            section: section,
            ordinal: ordinal,
            word: word,
            length: String.length(word)
          }
        end)
      )
    end)
  end

  def sync_title!(resource, id) do
    {kind, ^resource} = Enum.find(@resources, &(elem(&1, 1) == resource))
    fields = title_fields(kind)

    if fields != [] do
      table = AshPostgres.DataLayer.Info.table(resource)

      row =
        Atlas.Repo.one!(
          from r in table,
            where: r.id == type(^id, Ecto.UUID),
            lock: "FOR UPDATE",
            select: map(r, ^fields)
        )

      put_title!(kind, id, title(kind, row))
    end
  end

  defp title_fields(:campaign), do: [:name]
  defp title_fields(:session), do: [:number, :title]
  defp title_fields(:character), do: [:name]
  defp title_fields(:note), do: [:title]
  defp title_fields(:player_log), do: []

  defp title(:campaign, row), do: row.name
  defp title(:character, row), do: row.name || "Unnamed character"
  defp title(:note, row), do: row.title

  defp title(:session, row),
    do: if(row.title, do: "Session #{row.number}: #{row.title}", else: "Session #{row.number}")

  defp title(:player_log, _row), do: nil

  defp put_title!(kind, id, title) do
    words = Match.terms(title)
    put_words!(kind, id, "$title", words)

    Atlas.Repo.insert_all(
      "search_titles",
      [
        %{
          kind: to_string(kind),
          record_id: Ecto.UUID.dump!(id),
          title: title,
          words: Enum.filter(words, &(byte_size(&1) <= 1_000))
        }
      ],
      conflict_target: [:kind, :record_id],
      on_conflict: {:replace, [:title, :words]}
    )
  end

  defp marker(document) do
    marker = "ATLAS" <> Base.encode16(:crypto.strong_rand_bytes(16)) <> "MENTION"
    if String.contains?(Jason.encode!(document), marker), do: marker(document), else: marker
  end

  def render(blocks, labels, campaign_id) do
    Enum.map(blocks, fn block ->
      text =
        Enum.map_join(block["parts"], fn
          %{"text" => text} ->
            text

          %{"kind" => kind, "id" => id} ->
            Map.get(labels, {campaign_id, kind, id}, "Restricted entry")
        end)

      words =
        cond do
          is_list(block["words"]) ->
            block["words"]

          is_list(block["literal_words"]) and block["joined_mentions"] == false ->
            labels_words =
              Enum.flat_map(block["parts"], fn
                %{"kind" => kind, "id" => id} ->
                  labels
                  |> Map.get({campaign_id, kind, id}, "Restricted entry")
                  |> Match.terms()

                _ ->
                  []
              end)

            Enum.uniq(block["literal_words"] ++ labels_words)

          true ->
            nil
        end

      %{id: block["id"], text: text, words: words}
    end)
  end

  def backfill! do
    Enum.each(@resources, fn {kind, resource} ->
      table = AshPostgres.DataLayer.Info.table(resource)
      sections = Atlas.RichText.sections(resource)

      attributes = [
        :id
        | title_fields(kind) ++
            Enum.flat_map(
              sections,
              &[Atlas.RichText.json_attribute(&1), Atlas.RichText.revision_attribute(&1)]
            )
      ]

      backfill_batch(table, kind, sections, attributes, nil)
    end)
  end

  defp backfill_batch(table, kind, sections, attributes, after_id) do
    query = from r in table, order_by: r.id, limit: 200, select: r.id
    query = if after_id, do: from(r in query, where: r.id > ^after_id), else: query
    ids = Atlas.Repo.all(query)

    Enum.each(ids, fn id ->
      {:ok, :ok} =
        Atlas.Repo.transaction(fn ->
          # A content save locks the same parent row. Reload after taking that lock so a
          # concurrent save cannot be replaced by the content from an earlier batch scan.
          row =
            Atlas.Repo.one(
              from r in table, where: r.id == ^id, lock: "FOR UPDATE", select: map(r, ^attributes)
            )

          if row do
            title = title(kind, row)
            if title, do: put_title!(kind, Ecto.UUID.load!(id), title)

            Enum.each(sections, fn section ->
              put!(
                kind,
                Ecto.UUID.load!(id),
                section,
                Map.fetch!(row, Atlas.RichText.json_attribute(section)),
                Map.fetch!(row, Atlas.RichText.revision_attribute(section))
              )
            end)
          end

          :ok
        end)
    end)

    if length(ids) == 200,
      do: backfill_batch(table, kind, sections, attributes, List.last(ids))
  end
end
