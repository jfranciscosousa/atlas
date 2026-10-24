defmodule Atlas.Search do
  @moduledoc """
  Shared search for content the actor may read. Campaign scope is optional.

  Authorized list actions and field policies run before matching, ranking, and snippets.
  Mention labels are resolved separately for each campaign with the actor's access.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Search.{Projection, Reader}

  @blocks_per_section 3
  @snippet_length 300

  @impl true
  def run(input, _opts, %{actor: actor}) do
    args = input.arguments
    terms = Atlas.Search.Match.terms(args.query)

    with :ok <- query_terms(terms) do
      {all_entries, campaigns} = Reader.entries(actor, args[:campaign_id])
      kinds = args[:kinds] || [:campaign, :session, :character, :note, :player_log]

      if args[:campaign_id] && campaigns == [] do
        {:error, error(:campaign_id, "is not a campaign that you can read")}
      else
        entries = Enum.filter(all_entries, &(&1.kind in kinds and not &1.archived?))
        labels = Reader.labels(all_entries)
        matches = Reader.matches(entries, terms, actor, labels)
        sections = Reader.sections(matches) |> Enum.group_by(&{&1.kind, &1.id})
        entry_map = Map.new(entries, &{{to_string(&1.kind), &1.id}, &1})

        title_keys =
          for {key, title} <- matches.titles,
              length(title.matched) == length(terms),
              Map.has_key?(entry_map, key),
              do: key

        word_matches = matches.word_matches

        {hits, cache} =
          (title_keys ++ Map.keys(sections))
          |> Enum.uniq()
          |> Enum.map_reduce(word_matches, fn key, cache ->
            entry = Map.fetch!(entry_map, key)

            documents =
              Map.get(sections, {to_string(entry.kind), entry.id}, [])
              |> Enum.map(
                &{String.to_existing_atom(&1.section),
                 Projection.render(&1.blocks, labels, entry.campaign_id)}
              )

            title = Map.get(matches.titles, key, %{matched: [], exact: []})
            hit(entry, documents, terms, title, cache)
          end)

        hits =
          hits
          |> List.flatten()
          |> Enum.sort_by(&{-&1.exact_match, not &1.title_match, -&1.score, &1.title, &1.id})

        {:ok,
         %{
           hits:
             hits
             |> Enum.take(args.limit)
             |> Enum.map(&finish_hit(&1, cache)),
           more: length(hits) > args.limit
         }}
      end
    else
      {:error, {field, message}} -> {:error, error(field, message)}
    end
  end

  defp query_terms([]), do: {:error, {:query, "must contain letters or numbers"}}
  defp query_terms(_terms), do: :ok

  defp hit(entry, documents, terms, title_matches, cache) do
    %{kind: kind, id: id, title: title} = entry
    missing = terms -- title_matches.matched
    missing_exact = terms -- title_matches.exact

    {documents, cache} =
      Enum.map_reduce(documents, cache, fn {section, flat}, cache ->
        {blocks, cache} = Enum.map_reduce(flat, cache, &analyze(&1, terms, &2))
        {{section, blocks}, cache}
      end)

    sections =
      for {section, flat} <- documents,
          covers?(flat, missing, :matched),
          found = Enum.filter(flat, &(&1.matched != [])),
          found != [] do
        %{
          section: section,
          blocks:
            found
            |> Enum.take(@blocks_per_section)
            |> Enum.map(&%{id: &1.id, text: &1.text}),
          count: Enum.sum(Enum.map(found, & &1.count))
        }
      end

    title_match = missing == []

    if title_match or sections != [] do
      {[
         %{
           kind: kind,
           id: id,
           title: title,
           campaign_id: entry.campaign_id,
           campaign_name: entry.campaign_name,
           session_id: Map.get(entry, :session_id),
           sections: Enum.map(sections, &Map.delete(&1, :count)),
           title_match: title_match,
           exact_match:
             if(
               missing_exact == [] or
                 Enum.any?(documents, fn {_section, flat} ->
                   covers?(flat, missing_exact, :exact)
                 end),
               do: 1,
               else: 0
             ),
           score: Enum.sum(Enum.map(sections, & &1.count))
         }
       ], cache}
    else
      {[], cache}
    end
  end

  defp finish_hit(hit, cache) do
    hit
    |> Map.drop([:exact_match, :title_match, :score])
    |> Map.update!(:sections, fn sections ->
      Enum.map(sections, fn section ->
        Map.update!(section, :blocks, fn blocks ->
          Enum.map(blocks, &%{&1 | text: snippet(&1.text, cache)})
        end)
      end)
    end)
  end

  defp covers?(blocks, terms, field),
    do: Enum.all?(terms, fn term -> Enum.any?(blocks, &(term in Map.fetch!(&1, field))) end)

  defp analyze(block, terms, cache) do
    words = Map.get(block, :words) || Atlas.Search.Match.terms(block.text)

    {matches, cache} =
      Enum.map_reduce(words, cache, fn word, cache ->
        case Map.fetch(cache, word) do
          {:ok, matches} ->
            {matches, cache}

          :error ->
            matches =
              if Map.get(block, :words),
                do: [],
                else: Enum.filter(terms, &Atlas.Search.Match.matches?(word, &1))

            {matches, Map.put(cache, word, matches)}
        end
      end)

    {Map.merge(block, %{
       matched: matches |> List.flatten() |> Enum.uniq(),
       exact: Enum.filter(terms, fn term -> Enum.any?(words, &String.contains?(&1, term)) end),
       count: Enum.sum(Enum.map(matches, &length/1))
     }), cache}
  end

  # A window of the text around the first word that occurs in it.
  defp snippet(text, cache) do
    # Use original-text offsets: accent normalization can change the text length.
    start =
      Regex.scan(~r/[^\s\p{P}]+/u, text, return: :index)
      |> Enum.find_value(0, fn [{offset, length}] ->
        word = binary_part(text, offset, length)

        if Enum.any?(Atlas.Search.Match.terms(word), &(Map.get(cache, &1, []) != [])),
          do: String.length(binary_part(text, 0, offset))
      end)
      |> Kernel.-(100)
      |> max(0)

    window = String.slice(text, start, @snippet_length)
    prefix = if start > 0, do: "…", else: ""
    suffix = if start + @snippet_length < String.length(text), do: "…", else: ""
    prefix <> window <> suffix
  end

  defp error(field, message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: field, message: message)
end
