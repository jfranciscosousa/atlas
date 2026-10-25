defmodule Atlas.Content.EntryRelation.CheckEnds do
  @moduledoc """
  Both ends exist in the campaign, as the actor reads them, and are not archived. Each end is of
  the kind that the request says, and the relation allows that pair of kinds
  (`Atlas.Content.RelationSpec`). An entry is not related to itself. A symmetric relation, such as
  `:allied_with`, exists once for a pair, whichever end is first.
  """
  use Ash.Resource.Validation

  require Ash.Query

  alias Atlas.Campaigns.Character
  alias Atlas.Content.{Entry, EntryRelation, RelationSpec}

  @impl true
  def validate(changeset, _opts, %{actor: actor}) do
    get = &Ash.Changeset.get_attribute(changeset, &1)

    with {:ok, from_kind, to_kind} <- kinds(get),
         :ok <- allowed(get.(:relation), from_kind, to_kind),
         :ok <- distinct(get.(:from_id), get.(:to_id)),
         :ok <- end_exists(:from_id, from_kind, get.(:from_id), get.(:campaign_id), actor),
         :ok <- end_exists(:to_id, to_kind, get.(:to_id), get.(:campaign_id), actor) do
      symmetric_free(get.(:relation), get.(:from_id), get.(:to_id))
    end
  end

  defp kinds(get) do
    case {get.(:from_kind), get.(:to_kind)} do
      {from, to} when not is_nil(from) and not is_nil(to) -> {:ok, from, to}
      # The missing end already carries its own error.
      _ -> :ok
    end
  end

  defp allowed(nil, _from, _to), do: :ok

  defp allowed(relation, from, to) do
    if RelationSpec.allowed?(relation, from, to),
      do: :ok,
      else: {:error, field: :relation, message: "does not join a #{from} to a #{to}"}
  end

  defp distinct(id, id), do: {:error, field: :to_id, message: "must differ from the first end"}
  defp distinct(_from, _to), do: :ok

  defp end_exists(field, :character, id, campaign_id, actor) do
    case Ash.get(Character, id, actor: actor, not_found_error?: false) do
      {:ok, %Character{campaign_id: ^campaign_id}} -> :ok
      _ -> {:error, field: field, message: "is not a character of this campaign"}
    end
  end

  defp end_exists(field, kind, id, campaign_id, actor) do
    case Ash.get(Entry, id, actor: actor, not_found_error?: false) do
      {:ok, %Entry{kind: ^kind, campaign_id: ^campaign_id, archived_at: nil}} ->
        :ok

      _ ->
        {:error, field: field, message: "is not an active #{kind} of this campaign"}
    end
  end

  defp symmetric_free(nil, _from, _to), do: :ok

  defp symmetric_free(relation, from_id, to_id) do
    reverse =
      EntryRelation
      |> Ash.Query.filter(relation == ^relation and from_id == ^to_id and to_id == ^from_id)
      |> Ash.exists?(authorize?: false)

    if RelationSpec.symmetric?(relation) and reverse,
      do: {:error, field: :to_id, message: "These two are already related this way."},
      else: :ok
  end
end
