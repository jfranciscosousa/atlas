defmodule Atlas.Content.EntryField.SetPosition do
  @moduledoc """
  A new field, and a restored one, goes last in the order of its kind in its campaign.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      campaign_id = Ash.Changeset.get_attribute(changeset, :campaign_id)
      kind = Ash.Changeset.get_attribute(changeset, :kind)

      %{rows: [[next]]} =
        Ecto.Adapters.SQL.query!(
          Atlas.Repo,
          """
          SELECT COALESCE(MAX(position) + 1, 0)
          FROM entry_field_definitions
          WHERE campaign_id = $1 AND kind = $2 AND id <> $3
          """,
          [
            Ecto.UUID.dump!(campaign_id),
            Atom.to_string(kind),
            Ecto.UUID.dump!(changeset.data.id || Ecto.UUID.generate())
          ]
        )

      Ash.Changeset.force_change_attribute(changeset, :position, next)
    end)
  end
end
