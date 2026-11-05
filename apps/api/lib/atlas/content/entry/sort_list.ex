defmodule Atlas.Content.Entry.SortList do
  @moduledoc """
  Orders the `list` action by its `sort` argument. The app and MCP use the same argument.

    * `name`: A to Z.
    * `last_edited`: the entry edited last comes first. Saving the secret notes is no edit.
    * `last_created`: the entry created last comes first.
    * `last_mentioned`: the entry in the latest session log comes first. An entry that no log
      mentions comes last.

  A tie falls back to the name, so the order never changes between two reads.

  `last_mentioned` orders in memory. The list is never paged, so every row is read anyway, and
  the number of the latest session comes from one query for the whole list.
  """
  use Ash.Resource.Preparation

  alias Atlas.Content.Entry.LastSessionNumber

  @impl true
  def prepare(query, _opts, _context) do
    case Ash.Query.get_argument(query, :sort) do
      :last_edited ->
        Ash.Query.sort(query, edited_at: :desc, name: :asc, id: :asc)

      :last_created ->
        Ash.Query.sort(query, inserted_at: :desc, name: :asc, id: :asc)

      :last_mentioned ->
        query
        |> Ash.Query.sort(name: :asc, id: :asc)
        # A caller may select fewer fields. The mention lookup needs these.
        |> Ash.Query.ensure_selected([:id, :kind, :campaign_id])
        |> Ash.Query.after_action(&sort_by_latest_mention/2)

      _name ->
        Ash.Query.sort(query, name: :asc, id: :asc)
    end
  end

  # The records are already authorized. The query reads only session numbers that every member of
  # the campaign reads. `Enum.sort_by/2` is stable, so the name order stays as a tie-break.
  defp sort_by_latest_mention(_query, records) do
    latest = LastSessionNumber.by_entry(records)

    sorted =
      Enum.sort_by(records, fn entry ->
        case Map.fetch(latest, entry.id) do
          {:ok, number} -> {0, -number}
          :error -> {1, 0}
        end
      end)

    {:ok, sorted}
  end
end
