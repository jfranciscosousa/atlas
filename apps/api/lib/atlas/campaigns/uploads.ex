defmodule Atlas.Campaigns.Uploads do
  @moduledoc """
  Accepts an image for one section of a campaign. Authorization comes first, so an
  unauthorized caller never costs image-processing time or storage.
  """

  alias Atlas.Campaigns.{Campaign, Image}
  alias Atlas.Images.Processor

  @spec upload_image(Atlas.Accounts.User.t(), String.t(), String.t(), Path.t()) ::
          {:ok, Image.t()} | {:error, :not_found | Processor.error()}
  def upload_image(actor, campaign_id, section_name, path) do
    with {:ok, section} <- section(section_name),
         {:ok, campaign} <- fetch_campaign(campaign_id, actor),
         true <- Ash.can?({campaign, :"save_#{section}"}, actor) || {:error, :not_found},
         :ok <- check_size(path),
         {:ok, processed} <- path |> File.read!() |> Processor.process(),
         key = "campaigns/#{campaign.id}/images/#{Ecto.UUID.generate()}.webp",
         :ok <- Atlas.Storage.put(key, processed.webp, "image/webp") do
      Ash.create(
        Image,
        %{
          campaign_id: campaign.id,
          section: section,
          storage_key: key,
          byte_size: byte_size(processed.webp),
          width: processed.width,
          height: processed.height,
          animated: processed.animated?
        },
        actor: actor
      )
    end
  end

  # Compare strings so a client can never mint atoms.
  defp section(name) do
    case Enum.find(Atlas.RichText.sections(Campaign), &(Atom.to_string(&1) == name)) do
      nil -> {:error, :not_found}
      section -> {:ok, section}
    end
  end

  defp fetch_campaign(id, actor) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Ash.get(Campaign, uuid, actor: actor) do
          {:ok, campaign} -> {:ok, campaign}
          {:error, _} -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp check_size(path) do
    case File.stat(path) do
      {:ok, %{size: 0}} ->
        {:error, :unsupported_type}

      {:ok, %{size: size}} ->
        if size <= Processor.max_bytes(), do: :ok, else: {:error, :too_large}

      _ ->
        {:error, :unreadable}
    end
  end
end
