defmodule Atlas.Content.Entry.VerifyImage do
  @moduledoc """
  The portrait or cover of an entry is an image ID, as in a document. The image must exist.
  The check takes a shared lock on the image, so cleanup cannot delete it before the entry commits.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    with true <- Ash.Changeset.changing_attribute?(changeset, :image_id),
         image_id when not is_nil(image_id) <- Ash.Changeset.get_attribute(changeset, :image_id) do
      Ash.Changeset.before_action(changeset, fn changeset ->
        if Atlas.Images.Image.all_exist?([image_id]),
          do: changeset,
          else:
            Ash.Changeset.add_error(changeset,
              field: :image_id,
              message: "is not an image that exists"
            )
      end)
    else
      _ -> changeset
    end
  end
end
