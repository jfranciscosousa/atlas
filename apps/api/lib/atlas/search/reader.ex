defmodule Atlas.Search.Reader do
  @moduledoc false
  require Ash.Query
  import Ecto.Query

  alias Atlas.Campaigns.{Campaign, Character, PlayerLog, Session}
  alias Atlas.Content.{Entry, Note}
  alias Atlas.Search.{Match, Projection}

  def entries(actor, campaign_id) do
    campaigns = read(Campaign, actor, [:id, :name], campaign_id)

    if campaigns == [], do: {[], []}, else: campaign_entries(campaigns, actor)
  end

  defp campaign_entries(campaigns, actor) do
    campaign_ids = Enum.map(campaigns, & &1.id)
    sessions = read(Session, actor, [:id, :campaign_id, :number, :title], campaign_ids)
    session_map = Map.new(sessions, &{&1.id, &1})
    characters = read(Character, actor, [:id, :campaign_id, :name], campaign_ids)
    notes = read(Note, actor, [:id, :campaign_id, :title, :archived_at], campaign_ids)
    world = read(Entry, actor, [:id, :campaign_id, :kind, :name, :archived_at], campaign_ids)

    logs =
      PlayerLog
      |> Ash.Query.filter(session_id in ^Map.keys(session_map))
      |> Ash.Query.select([:id, :session_id])
      |> Ash.Query.load(:author_name)
      |> Ash.read!(actor: actor)

    entries =
      Enum.map(campaigns, &entry(:campaign, &1, &1.id, &1.name)) ++
        Enum.map(sessions, &entry(:session, &1, &1.campaign_id, session_title(&1))) ++
        Enum.map(
          characters,
          &entry(:character, &1, &1.campaign_id, &1.name || "Unnamed character")
        ) ++
        Enum.map(
          notes,
          &(entry(:note, &1, &1.campaign_id, &1.title)
            |> Map.put(:archived?, not is_nil(&1.archived_at)))
        ) ++
        Enum.map(
          world,
          &(entry(&1.kind, &1, &1.campaign_id, &1.name)
            |> Map.put(:archived?, not is_nil(&1.archived_at)))
        ) ++
        Enum.map(logs, fn log ->
          session = Map.fetch!(session_map, log.session_id)

          entry(
            :player_log,
            log,
            session.campaign_id,
            "#{session_title(session)}: log of #{log.author_name}"
          )
          |> Map.put(:session_id, log.session_id)
        end)

    names = Map.new(campaigns, &{&1.id, &1.name})

    {Enum.map(entries, &Map.put(&1, :campaign_name, Map.fetch!(names, &1.campaign_id))),
     campaigns}
  end

  defp read(resource, actor, fields, campaign_ids) do
    query = Ash.Query.select(resource, fields)

    query =
      case {resource, campaign_ids} do
        {Campaign, nil} -> query
        {Campaign, id} -> Ash.Query.filter(query, id == ^id)
        {_, ids} -> Ash.Query.filter(query, campaign_id in ^ids)
      end

    Ash.read!(query, actor: actor)
  end

  defp entry(kind, record, campaign_id, title),
    do: %{kind: kind, id: record.id, campaign_id: campaign_id, title: title, archived?: false}

  defp session_title(%{number: number, title: nil}), do: "Session #{number}"
  defp session_title(%{number: number, title: title}), do: "Session #{number}: #{title}"

  def labels(entries) do
    entries
    |> Enum.filter(&(&1.kind in Atlas.Kinds.mention_kinds()))
    |> Map.new(fn entry ->
      {{entry.campaign_id, to_string(entry.kind), entry.id},
       if(entry.archived?, do: "Deleted entry", else: entry.title)}
    end)
  end

  def matches([], _terms, _actor, _labels),
    do: %{
      words: [],
      word_matches: %{},
      scopes: [],
      titles: %{},
      mention_keys: [],
      restricted_match?: false
    }

  def matches(entries, terms, actor, labels) do
    scopes = section_scopes(entries, actor)

    title_scope =
      (Enum.map(entries, &{to_string(&1.kind), &1.id}) ++
         for({{_, kind, id}, label} <- labels, label != "Deleted entry", do: {kind, id}))
      |> Enum.uniq()
      |> Enum.group_by(&elem(&1, 0), &Ecto.UUID.dump!(elem(&1, 1)))
      |> Enum.reduce(dynamic(false), fn {kind, ids}, scope ->
        dynamic(
          [w],
          ^scope or (w.kind == ^kind and w.record_id in ^ids and w.section == "$title")
        )
      end)

    word_scope =
      Enum.reduce(scopes, title_scope, fn {kind, section, ids}, scope ->
        dynamic(
          [w],
          ^scope or (w.kind == ^kind and w.section == ^section and w.record_id in ^ids)
        )
      end)

    word_matches = matching_words_by_term(terms, word_scope)
    words = word_matches |> Map.values() |> Enum.flat_map(&MapSet.to_list/1) |> Enum.uniq()

    ids =
      (Enum.map(entries, & &1.id) ++ Enum.map(labels, fn {{_, _, id}, _} -> id end))
      |> Enum.uniq()
      |> Enum.map(&Ecto.UUID.dump!/1)

    long_words = Enum.filter(words, &(byte_size(&1) > 1_000))

    long_title_ids =
      from w in "search_words",
        where: w.section == "$title" and w.word in ^long_words,
        select: w.record_id

    projected_titles =
      Atlas.Repo.all(
        from t in "search_titles",
          where: t.record_id in ^ids,
          where:
            fragment("? && ?::text[]", t.words, ^words) or
              t.record_id in subquery(long_title_ids),
          select: %{kind: t.kind, id: t.record_id, words: t.words, title: t.title}
      )

    dynamic_titles =
      [
        "Restricted entry",
        "Deleted entry" | for(entry <- entries, entry.kind == :player_log, do: entry.title)
      ]
      |> Enum.uniq()
      |> Map.new(&{&1, Match.terms(&1)})

    dynamic_words = dynamic_titles |> Map.values() |> List.flatten() |> Enum.uniq()

    word_matches =
      Map.new(word_matches, fn {term, matching} ->
        {term,
         Enum.reduce(dynamic_words, matching, fn word, acc ->
           if Match.matches?(word, term), do: MapSet.put(acc, word), else: acc
         end)}
      end)

    dynamic_matches =
      Map.new(dynamic_titles, fn {title, words} -> {title, title_match(words, word_matches)} end)

    titles =
      Map.new(projected_titles, fn row ->
        title_words = if long_words == [], do: row.words, else: Match.terms(row.title)
        {{row.kind, Ecto.UUID.load!(row.id)}, title_match(title_words, word_matches)}
      end)

    titles =
      Enum.reduce(entries, titles, fn
        %{kind: :player_log} = entry, acc ->
          Map.put(acc, {"player_log", entry.id}, Map.fetch!(dynamic_matches, entry.title))

        _, acc ->
          acc
      end)

    mention_keys =
      for {{_campaign, kind, id}, label} <- labels,
          match =
            if(label == "Deleted entry", do: dynamic_matches[label], else: titles[{kind, id}]),
          match && match.matched != [],
          do: kind <> ":" <> id

    %{
      words: words,
      word_matches:
        Enum.reduce(word_matches, %{}, fn {term, words}, matches ->
          Enum.reduce(words, matches, fn word, matches ->
            Map.update(matches, word, [term], &[term | &1])
          end)
        end),
      scopes: scopes,
      titles: titles,
      mention_keys: Enum.uniq(mention_keys),
      restricted_match?: dynamic_matches["Restricted entry"].matched != []
    }
  end

  defp title_match(words, word_matches) do
    %{
      matched:
        for(
          {term, matching} <- word_matches,
          Enum.any?(words, &MapSet.member?(matching, &1)),
          do: term
        ),
      exact:
        for({term, _} <- word_matches, Enum.any?(words, &String.contains?(&1, term)), do: term)
    }
  end

  def sections(entries, terms, actor, labels),
    do: sections(matches(entries, terms, actor, labels))

  defp section_scopes(entries, actor) do
    entries_by_kind = Enum.group_by(entries, & &1.kind)

    Enum.flat_map(Projection.resources(), fn {kind, resource} ->
      ids = Enum.map(Map.get(entries_by_kind, kind, []), & &1.id)

      if ids == [] do
        []
      else
        query = Ash.Query.for_read(resource, :read, %{}, actor: actor)
        fields = Enum.map(Atlas.RichText.sections(resource), &Atlas.RichText.json_attribute/1)

        {:ok, policies} =
          Ash.Policy.Authorizer.evaluate_field_policies(query, fields, actor: actor)

        Enum.flat_map(Atlas.RichText.sections(resource), fn section ->
          allowed_ids =
            case Map.fetch!(policies, Atlas.RichText.json_attribute(section)) do
              true ->
                ids

              false ->
                []

              {:filter, expression} ->
                resource
                |> Ash.Query.filter(id in ^ids)
                |> Ash.Query.do_filter(expression)
                |> Ash.Query.select([:id])
                |> Ash.read!(actor: actor)
                |> Enum.map(& &1.id)
            end

          if allowed_ids == [],
            do: [],
            else: [
              {to_string(kind), to_string(section), Enum.map(allowed_ids, &Ecto.UUID.dump!/1)}
            ]
        end)
      end
    end)
  end

  def sections(matches) do
    %{words: words, mention_keys: mention_keys, restricted_match?: restricted_match?} = matches

    Enum.flat_map(matches.scopes, fn {kind, section, allowed_ids} ->
      Atlas.Repo.all(
        from s in "search_sections",
          where:
            s.kind == ^kind and s.section == ^section and
              s.record_id in ^allowed_ids,
          where:
            fragment("? && ?::text[]", s.words, ^words) or
              fragment("? && ?::text[]", s.mention_keys, ^mention_keys) or
              (s.has_mentions and ^restricted_match?) or s.joined_mentions or s.has_long_words,
          select: %{kind: s.kind, id: s.record_id, section: s.section, blocks: s.blocks}
      )
      |> Enum.map(&%{&1 | id: Ecto.UUID.load!(&1.id)})
    end)
  end

  # Trigrams accelerate substring candidates. The length-indexed union is essential: a
  # valid edit-distance match can have no common trigrams (for example abcd / axcd).
  # No similarity threshold or candidate limit may discard those words.
  def matching_words(terms) do
    terms
    |> matching_words_by_term(dynamic(true))
    |> Map.values()
    |> Enum.flat_map(&MapSet.to_list/1)
    |> Enum.uniq()
  end

  defp matching_words_by_term(terms, scope) do
    Map.new(terms, fn term ->
      tolerance = if String.length(term) >= 8, do: 2, else: 1
      length = String.length(term)

      escaped =
        term
        |> String.replace("\\", "\\\\")
        |> String.replace("%", "\\%")
        |> String.replace("_", "\\_")

      pattern = "%" <> escaped <> "%"
      candidates = dynamic([w], like(w.word, ^pattern))

      candidates =
        if length >= 4,
          do:
            dynamic(
              [w],
              ^candidates or
                (w.length >= ^(length - tolerance) and w.length <= ^(length + tolerance))
            ),
          else: candidates

      query =
        from w in "search_words",
          where: ^scope,
          where: ^candidates,
          distinct: true,
          select: w.word

      words = query |> Atlas.Repo.all() |> Enum.filter(&Match.matches?(&1, term))
      {term, MapSet.new(words)}
    end)
  end
end
