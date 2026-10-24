defmodule Atlas.Search.Sync do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context), do: attach(changeset)

  @impl true
  def atomic(changeset, _opts, _context), do: {:ok, attach(changeset)}

  defp attach(changeset) do
    Ash.Changeset.after_action(changeset, fn changeset, record ->
      sections = Atlas.RichText.sections(changeset.resource)

      sections =
        if changeset.action_type == :create,
          do: sections,
          else:
            Enum.filter(
              sections,
              &Ash.Changeset.changing_attribute?(changeset, Atlas.RichText.json_attribute(&1))
            )

      if changeset.action_type == :create or
           Enum.any?([:name, :title, :number], &Ash.Changeset.changing_attribute?(changeset, &1)),
         do: Atlas.Search.Projection.sync_title!(changeset.resource, record.id)

      if sections != [],
        do: Atlas.Search.Projection.sync!(changeset.resource, record.id, sections)

      {:ok, record}
    end)
  end
end
