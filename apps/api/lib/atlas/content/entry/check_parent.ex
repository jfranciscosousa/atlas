defmodule Atlas.Content.Entry.CheckParent do
  @moduledoc """
  Only a location has a parent, and the parent is a location of the same campaign that the actor
  may read and that is not archived. A location is never its own ancestor.

  The check runs inside the action's transaction, after a lock on the campaign's location tree.
  Two moves at once then cannot make a cycle.
  """
  use Ash.Resource.Change

  alias Atlas.Content.Entry

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    if changeset.action_type == :create or
         Ash.Changeset.changing_attribute?(changeset, :parent_id) do
      Ash.Changeset.before_action(changeset, &check(&1, actor))
    else
      changeset
    end
  end

  defp check(changeset, actor) do
    parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    campaign_id = Ash.Changeset.get_attribute(changeset, :campaign_id)
    id = changeset.data.id

    cond do
      is_nil(parent_id) -> changeset
      kind != :location -> error(changeset, "Only a location has a parent location.")
      parent_id == id -> error(changeset, "A location cannot be its own parent.")
      true -> check_parent(changeset, actor, parent_id, campaign_id, id)
    end
  end

  defp check_parent(changeset, actor, parent_id, campaign_id, id) do
    lock(campaign_id)

    case Ash.get(Entry, parent_id, actor: actor, not_found_error?: false) do
      {:ok, %Entry{kind: :location, campaign_id: ^campaign_id, archived_at: nil}} ->
        if id && id in ancestors(parent_id),
          do: error(changeset, "A location cannot be inside one of its own locations."),
          else: changeset

      _ ->
        error(changeset, "Choose a location of this campaign.")
    end
  end

  defp lock(campaign_id) do
    Ecto.Adapters.SQL.query!(
      Atlas.Repo,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      ["entry-parents:#{campaign_id}"]
    )
  end

  # The IDs of the entry and of everything above it.
  defp ancestors(entry_id) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Atlas.Repo,
        """
        WITH RECURSIVE chain(id, parent_id) AS (
          SELECT id, parent_id FROM entries WHERE id = $1
          UNION
          SELECT e.id, e.parent_id FROM entries e JOIN chain c ON e.id = c.parent_id
        )
        SELECT id FROM chain
        """,
        [Ecto.UUID.dump!(entry_id)]
      )

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  defp error(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :parent_id, message: message)
end
