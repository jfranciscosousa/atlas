defmodule Atlas.Mcp.Search do
  @moduledoc """
  Finds words in the names and the text of one campaign, as the actor. It implements `search`.

  It reads the entries with their normal `:list` actions, so the read policies and field
  policies decide what the actor can find: a hidden section, such as the GM prep, is never
  searched. The text is plain: a mention reads as the name the actor may see, and an image as
  `[image: name - caption]`. Every word of the query must occur, in any order, in the name of
  the entry together with one section. A hit lists the blocks that hold a word, with their ID.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Campaigns.{Campaign, Character, PlayerLog, Session}
  alias Atlas.Content.Note
  alias Atlas.RichText
  alias Atlas.RichText.{Mentions, PlainText}

  @text_opts [links: false, at: false, images: true]
  @blocks_per_section 3
  @snippet_length 300

  @impl true
  def run(input, _opts, %{actor: actor}) do
    args = input.arguments
    terms = args.query |> String.downcase() |> String.split()

    with {:ok, campaign} <- campaign(args.campaign_id, actor) do
      kinds = args[:kinds] || [:campaign, :session, :character, :note, :player_log]
      entries = Enum.flat_map(kinds, &entries(&1, campaign, actor))

      labels =
        entries
        |> Enum.flat_map(fn {_kind, record, _title} -> documents(record) end)
        |> Enum.map(&elem(&1, 1))
        |> Mentions.labels(actor, campaign.id)

      hits =
        entries
        |> Enum.flat_map(&hit(&1, terms, labels))
        |> Enum.sort_by(&{&1.title_match, &1.score}, :desc)

      {:ok,
       %{
         hits: hits |> Enum.take(args.limit) |> Enum.map(&Map.drop(&1, [:title_match, :score])),
         more: length(hits) > args.limit
       }}
    else
      {:error, {field, message}} -> {:error, error(field, message)}
    end
  end

  defp campaign(id, actor) do
    case Ash.get(Campaign, id, actor: actor, not_found_error?: false) do
      {:ok, %Campaign{} = campaign} -> {:ok, campaign}
      _ -> {:error, {:campaign_id, "is not a campaign that you can read"}}
    end
  end

  defp entries(:campaign, campaign, _actor), do: [{:campaign, campaign, campaign.name}]

  defp entries(:session, campaign, actor) do
    for session <- list(Session, %{campaign_id: campaign.id}, actor),
        do: {:session, session, session_title(session)}
  end

  defp entries(:character, campaign, actor) do
    for character <- list(Character, %{campaign_id: campaign.id}, actor),
        do: {:character, character, character.name || "Unnamed character"}
  end

  defp entries(:note, campaign, actor) do
    for note <- list(Note, %{campaign_id: campaign.id}, actor), do: {:note, note, note.title}
  end

  defp entries(:player_log, campaign, actor) do
    for session <- list(Session, %{campaign_id: campaign.id}, actor),
        log <- list(PlayerLog, %{session_id: session.id}, actor, [:author_name]) do
      {:player_log, log, "#{session_title(session)}: log of #{log.author_name}"}
    end
  end

  defp list(resource, arguments, actor, load \\ []) do
    resource
    |> Ash.Query.for_read(:list, arguments, actor: actor)
    |> Ash.Query.load(load)
    |> Ash.read!()
  end

  defp session_title(%{number: number, title: nil}), do: "Session #{number}"
  defp session_title(%{number: number, title: title}), do: "Session #{number}: #{title}"

  # A field policy replaces a hidden section with a `%Ash.ForbiddenField{}`.
  defp documents(record) do
    for section <- RichText.sections(record.__struct__),
        blocks = Map.fetch!(record, RichText.json_attribute(section)),
        is_list(blocks),
        do: {section, blocks}
  end

  defp hit({kind, record, title}, terms, labels) do
    sections =
      for {section, blocks} <- documents(record),
          flat = PlainText.flat(blocks, [labels: labels] ++ @text_opts),
          text = Enum.map_join(flat, "\n", & &1.text),
          all?(title <> "\n" <> text, terms),
          found = Enum.filter(flat, &any?(&1.text, terms)),
          found != [] do
        %{
          section: section,
          blocks:
            found
            |> Enum.take(@blocks_per_section)
            |> Enum.map(&%{id: &1.id, text: snippet(&1.text, terms)}),
          count: Enum.sum(for block <- found, term <- terms, do: occurrences(block.text, term))
        }
      end

    title_match = all?(title, terms)

    if title_match or sections != [] do
      [
        %{
          kind: kind,
          id: record.id,
          title: title,
          sections: Enum.map(sections, &Map.delete(&1, :count)),
          title_match: title_match,
          score: Enum.sum(Enum.map(sections, & &1.count))
        }
      ]
    else
      []
    end
  end

  defp all?(text, terms) do
    text = String.downcase(text)
    Enum.all?(terms, &String.contains?(text, &1))
  end

  defp any?(text, terms) do
    text = String.downcase(text)
    Enum.any?(terms, &String.contains?(text, &1))
  end

  defp occurrences(text, term),
    do: text |> String.downcase() |> String.split(term) |> length() |> Kernel.-(1)

  # A window of the text around the first word that occurs in it.
  defp snippet(text, terms) do
    down = String.downcase(text)

    start =
      terms
      |> Enum.flat_map(fn term ->
        case String.split(down, term, parts: 2) do
          [before, _] -> [String.length(before)]
          _ -> []
        end
      end)
      |> Enum.min(fn -> 0 end)
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
