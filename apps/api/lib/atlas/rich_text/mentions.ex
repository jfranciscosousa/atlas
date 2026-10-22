defmodule Atlas.RichText.Mentions do
  @moduledoc """
  Names the entries that the mentions in some text point to, as one actor may read them.

  A text stores only the kind and the ID of a mention. The normal read policies decide what the
  actor may see: an entry that the actor cannot read has no name here, and the caller shows
  "Restricted entry". An archived note that the actor may read is "Deleted entry".
  """
  require Ash.Query

  alias Atlas.Campaigns.{Character, Session}
  alias Atlas.Content.Note
  alias Atlas.RichText.Document

  @resources %{"character" => Character, "session" => Session, "note" => Note}

  @doc "Map of `{kind, id}` to the name of the entry, for the mentions in `documents`."
  @spec labels([[map()] | nil], term()) :: %{{String.t(), String.t()} => String.t()}
  def labels(documents, actor) do
    documents
    |> Enum.flat_map(&Document.mention_refs/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {kind, ids} ->
      @resources
      |> Map.fetch!(kind)
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(actor: actor)
      |> Enum.map(&{{kind, &1.id}, label(kind, &1)})
    end)
    |> Map.new()
  end

  defp label("character", character), do: character.name || "Unnamed character"

  defp label("session", %{number: number, title: nil}), do: "Session #{number}"
  defp label("session", %{number: number, title: title}), do: "Session #{number}: #{title}"

  defp label("note", %{archived_at: nil, title: title}), do: title
  defp label("note", _archived), do: "Deleted entry"
end
