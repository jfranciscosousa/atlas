defmodule Atlas.Images.Uploads do
  @moduledoc """
  Accepts an image. Authorization comes first, so an unauthorized caller never costs
  image-processing time or storage.
  """

  alias Atlas.Images.{Image, Processor}

  @spec upload_image(Atlas.Accounts.User.t(), Path.t()) ::
          {:ok, Image.t()} | {:error, :not_found | Processor.error()}
  def upload_image(actor, path) do
    with true <- Ash.can?({Image, :create}, actor) || {:error, :not_found},
         :ok <- check_size(path),
         {:ok, processed} <- path |> File.read!() |> Processor.process(),
         key = "images/#{Ecto.UUID.generate()}.webp",
         :ok <- Atlas.Storage.put(key, processed.webp, "image/webp") do
      Ash.create(
        Image,
        %{
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
