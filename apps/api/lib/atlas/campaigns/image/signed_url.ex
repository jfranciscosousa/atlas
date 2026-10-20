defmodule Atlas.Campaigns.Image.SignedUrl do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Atlas.Campaigns.Image
  alias Atlas.Images.Parent

  @impl true
  def run(input, _opts, context) do
    %{id: id, parent_type: kind, parent_id: parent_id, section: section} = input.arguments

    # The parent and section named by the client must own the image: a copied ID from another
    # section or parent finds nothing. Then the actor must be able to read that section.
    Image
    |> Ash.Query.filter(
      id == ^id and parent_type == ^kind and parent_id == ^parent_id and section == ^section
    )
    |> Ash.read_one(actor: context.actor)
    |> case do
      {:ok, %Image{storage_key: key}} ->
        if Parent.section_readable?(kind, parent_id, section, context.actor),
          do: {:ok, Atlas.Storage.signed_url(key)},
          else: {:error, Ash.Error.Query.NotFound.exception(resource: Image)}

      {:ok, nil} ->
        {:error, Ash.Error.Query.NotFound.exception(resource: Image)}

      {:error, error} ->
        {:error, error}
    end
  end
end
