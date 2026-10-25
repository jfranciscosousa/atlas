defmodule Atlas.Content.Entry.ApplyCustomValues do
  @moduledoc """
  Applies the `custom_values` argument of a create or an update: a map of field ID to value.

  An ID must belong to an active custom field of the entry's kind in the entry's campaign.
  `Atlas.Content.EntryField.Value` checks the value by the type of the field, and an entry field
  must point to a non-archived entry of its target kind in the same campaign, which the actor
  reads. An empty value removes the key. The values of fields that the map leaves out stay, and so
  do the values of archived fields: restoring a field shows them again.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Atlas.Content.{Entry, EntryField}
  alias Atlas.Content.EntryField.Value

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    case Ash.Changeset.get_argument(changeset, :custom_values) do
      nil ->
        changeset

      values when is_map(values) ->
        Ash.Changeset.before_action(changeset, &merge_values(&1, values, actor))

      _other ->
        add_error(changeset, "must be a map of field IDs to values")
    end
  end

  defp merge_values(changeset, values, actor) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    campaign_id = Ash.Changeset.get_attribute(changeset, :campaign_id)

    fields =
      EntryField
      |> Ash.Query.filter(campaign_id == ^campaign_id and kind == ^kind and is_nil(archived_at))
      |> Ash.read!(actor: actor)
      |> Map.new(&{&1.id, &1})

    stored = stored(changeset)

    values
    |> Enum.reduce_while({:ok, stored}, fn {id, raw}, {:ok, acc} ->
      id = to_string(id)

      with {:ok, field} <-
             Map.fetch(fields, id) |> or_error("#{id} is not an active custom field of this kind"),
           {:ok, change} <- check(field, raw, campaign_id, actor) do
        {:cont, {:ok, put(acc, id, change)}}
      else
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, merged} -> Ash.Changeset.force_change_attribute(changeset, :custom_fields, merged)
      {:error, message} -> add_error(changeset, message)
    end
  end

  # An update merges into the row as it is now, under a lock, so two edits of different fields
  # cannot overwrite each other.
  defp stored(%{action_type: :create}), do: %{}

  defp stored(changeset) do
    %{rows: [[custom_fields]]} =
      Ecto.Adapters.SQL.query!(
        Atlas.Repo,
        "SELECT custom_fields FROM entries WHERE id = $1 FOR UPDATE",
        [Ecto.UUID.dump!(changeset.data.id)]
      )

    custom_fields
  end

  defp check(field, raw, campaign_id, actor) do
    case {field.type, Value.normalize(field, raw)} do
      {:entry, {:set, id}} -> check_target(field, id, campaign_id, actor)
      {_type, {:set, _value} = set} -> {:ok, set}
      {_type, :clear} -> {:ok, :clear}
      {_type, {:error, message}} -> {:error, prefix(field, message)}
    end
  end

  defp check_target(field, id, campaign_id, actor) do
    target_kind = EntryField.target_kind(field)

    case Ash.get(Entry, id, actor: actor, not_found_error?: false) do
      {:ok, %Entry{kind: ^target_kind, campaign_id: ^campaign_id, archived_at: nil}} ->
        {:ok, {:set, id}}

      _ ->
        {:error, "#{field.label} must be a #{target_kind} of this campaign"}
    end
  end

  defp put(acc, id, :clear), do: Map.delete(acc, id)
  defp put(acc, id, {:set, value}), do: Map.put(acc, id, value)

  defp prefix(field, message) do
    if String.starts_with?(message, field.label), do: message, else: "#{field.label} #{message}"
  end

  defp or_error({:ok, _} = ok, _message), do: ok
  defp or_error(:error, message), do: {:error, message}

  defp add_error(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :custom_values, message: message)
end
