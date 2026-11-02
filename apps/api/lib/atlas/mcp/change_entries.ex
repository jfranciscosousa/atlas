defmodule Atlas.Mcp.ChangeEntries do
  @moduledoc """
  Changes many world entries in one call, in one transaction: if one entry fails, nothing changes.
  It implements `set_entries_hidden`, `archive_entries` and `restore_entries`. The entries go
  through the same action as the single tool (`set_hidden`, `archive`, `restore`), as the actor, in
  one set-based update. The update policy of Entry filters the rows, so the number of queries does
  not grow with the number of entries.

  An entry that does not exist and one that the actor may not change are both missing from the
  result. Either one fails the call with the same error.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Atlas.Content.Entry

  @fields [:id, :kind, :name, :hidden, :archived_at]

  @impl true
  def run(input, opts, %{actor: actor}) do
    action = Keyword.fetch!(opts, :action)
    params = Map.take(input.arguments, Keyword.get(opts, :params, []))
    ids = Enum.uniq(input.arguments.ids)

    result =
      Atlas.Repo.transaction(fn ->
        case change(ids, action, params, actor) do
          {:ok, entries, notifications} ->
            {entries, notifications}

          {:error, index} ->
            Atlas.Repo.rollback(index)
        end
      end)

    case result do
      {:ok, {entries, notifications}} ->
        # Subscribers hear of the changes only after the transaction commits.
        Ash.Notifier.notify(notifications)
        {:ok, %{entries: entries}}

      {:error, index} ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :ids,
           message:
             "ids[#{index}] is not an entry that exists and that you may change. Nothing was changed"
         )}
    end
  end

  # The update policy is a filter, so an entry that the actor may not change is not updated. Every
  # ID must come back, or the call fails as a whole.
  defp change(ids, action, params, actor) do
    result =
      Entry
      |> Ash.Query.filter(id in ^ids)
      |> Ash.bulk_update(action, params,
        actor: actor,
        strategy: :atomic,
        return_records?: true,
        return_errors?: true,
        stop_on_error?: true,
        return_notifications?: true
      )

    with %Ash.BulkResult{status: :success, records: records} <- result,
         changed = Map.new(records, &{&1.id, &1}),
         [] <- Enum.reject(ids, &Map.has_key?(changed, &1)) do
      {:ok, Enum.map(ids, &Map.take(Map.fetch!(changed, &1), @fields)),
       result.notifications || []}
    else
      %Ash.BulkResult{records: records} ->
        {:error, first_missing(ids, records)}

      missing when is_list(missing) ->
        {:error, Enum.find_index(ids, &(&1 == hd(missing)))}
    end
  end

  defp first_missing(ids, records) do
    changed = MapSet.new(records || [], & &1.id)
    Enum.find_index(ids, &(not MapSet.member?(changed, &1))) || 0
  end
end
