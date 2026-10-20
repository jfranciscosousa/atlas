defmodule Atlas.RichText.Save do
  @moduledoc """
  Saves one section. The client's `expected_revision` becomes a database condition, so a stale
  or losing concurrent save updates zero rows and fails with `Ash.Error.Changes.StaleRecord`.
  """
  use Ash.Resource.Change

  import Ash.Expr

  alias Atlas.RichText
  alias Atlas.RichText.Document

  @impl true
  def change(changeset, opts, _context) do
    section = Keyword.fetch!(opts, :section)
    json = RichText.json_attribute(section)
    revision = RichText.revision_attribute(section)
    version = RichText.schema_version_attribute(section)

    expected = Ash.Changeset.get_argument(changeset, :expected_revision)

    cond do
      Ash.Changeset.get_argument(changeset, :schema_version) != Document.schema_version() ->
        Ash.Changeset.add_error(changeset,
          field: :schema_version,
          message: "is not a supported schema version"
        )

      # Ash skips the data layer when nothing changed, so a stale save with identical content
      # would pass. Fail fast on the loaded record; the filter below still guards races.
      Map.fetch!(changeset.data, revision) != expected ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.StaleRecord.exception(resource: changeset.resource)
        )

      true ->
        changeset
        |> Ash.Changeset.filter(expr(^ref(revision) == ^expected))
        |> Ash.Changeset.force_change_attribute(
          json,
          Ash.Changeset.get_argument(changeset, :json)
        )
        |> Ash.Changeset.force_change_attribute(version, Document.schema_version())
        |> Ash.Changeset.force_change_attribute(revision, expected + 1)
        |> verify_images(section, Ash.Changeset.get_argument(changeset, :json))
    end
  end

  # An invalid document already carries its own argument error.
  defp verify_images(changeset, _section, nil), do: changeset

  defp verify_images(changeset, section, json) do
    case Document.image_ids(json) do
      [] ->
        changeset

      ids ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          if Atlas.Images.Image.all_in_section?(
               Atlas.Images.Parent.kind(changeset.resource),
               changeset.data.id,
               section,
               ids
             ),
             do: changeset,
             else:
               Ash.Changeset.add_error(changeset,
                 field: :json,
                 message: "references an image that does not belong to this section"
               )
        end)
    end
  end
end
