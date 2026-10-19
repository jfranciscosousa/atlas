defmodule Atlas.Campaigns.Image.SignedUrl do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Atlas.Campaigns.Image

  @impl true
  def run(input, _opts, context) do
    %{id: id, campaign_id: campaign_id, section: section} = input.arguments

    # The campaign and section named by the client must own the image: a copied ID from
    # another section or campaign finds nothing. The read policy checks access.
    Image
    |> Ash.Query.filter(id == ^id and campaign_id == ^campaign_id and section == ^section)
    |> Ash.read_one(actor: context.actor)
    |> case do
      {:ok, %Image{storage_key: key}} -> {:ok, Atlas.Storage.signed_url(key)}
      {:ok, nil} -> {:error, Ash.Error.Query.NotFound.exception(resource: Image)}
      {:error, error} -> {:error, error}
    end
  end
end
