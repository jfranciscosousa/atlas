defmodule Atlas.Images.Image.SignedUrl do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias Atlas.Images.Image

  @impl true
  def run(input, _opts, context) do
    case Ash.get(Image, input.arguments.id, actor: context.actor) do
      {:ok, %Image{storage_key: key}} -> {:ok, Atlas.Storage.signed_url(key)}
      {:error, error} -> {:error, error}
    end
  end
end
