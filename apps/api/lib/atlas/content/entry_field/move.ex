defmodule Atlas.Content.EntryField.Move do
  @moduledoc """
  Moves an active field to a place in the order of its kind. The other active fields shift and
  keep their order. The change runs after a lock on the kind in its campaign, so two moves at once
  cannot give two fields the same place.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &move/1)
  end

  defp move(%{data: %{archived_at: %DateTime{}}} = changeset) do
    Ash.Changeset.add_error(changeset,
      field: :position,
      message: "has no place while archived; restore the field first"
    )
  end

  defp move(changeset) do
    field = changeset.data
    wanted = Ash.Changeset.get_argument(changeset, :position)

    lock(field)
    others = ids_in_order(field)
    index = min(wanted, length(others))
    order = List.insert_at(others, index, field.id)

    # The field is written too, so a stale struct cannot leave an old place in the table.
    order |> Enum.with_index() |> write()

    Ash.Changeset.force_change_attribute(changeset, :position, index)
  end

  defp lock(field) do
    Ecto.Adapters.SQL.query!(
      Atlas.Repo,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      ["entry-fields:#{field.campaign_id}:#{field.kind}"]
    )
  end

  defp ids_in_order(field) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Atlas.Repo,
        """
        SELECT id FROM entry_field_definitions
        WHERE campaign_id = $1 AND kind = $2 AND archived_at IS NULL AND id <> $3
        ORDER BY position, inserted_at, id
        """,
        [
          Ecto.UUID.dump!(field.campaign_id),
          Atom.to_string(field.kind),
          Ecto.UUID.dump!(field.id)
        ]
      )

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  defp write([]), do: :ok

  defp write(pairs) do
    {ids, positions} =
      pairs |> Enum.map(fn {id, index} -> {Ecto.UUID.dump!(id), index} end) |> Enum.unzip()

    Ecto.Adapters.SQL.query!(
      Atlas.Repo,
      """
      UPDATE entry_field_definitions f SET position = m.position
      FROM unnest($1::uuid[], $2::int[]) AS m(id, position)
      WHERE f.id = m.id
      """,
      [ids, positions]
    )
  end
end
