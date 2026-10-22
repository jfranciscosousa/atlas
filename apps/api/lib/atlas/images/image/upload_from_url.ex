defmodule Atlas.Images.Image.UploadFromUrl do
  @moduledoc """
  Downloads an image from a public URL and stores it like an upload from the web app: the same
  rights check, size limit, type check and WebP conversion.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Images.{Fetch, Uploads}

  @impl true
  def run(input, _opts, %{actor: actor}) do
    with {:ok, path} <- Fetch.download(input.arguments.url) do
      try do
        case Uploads.upload_image(actor, path) do
          {:ok, image} ->
            {:ok,
             %{
               id: image.id,
               width: image.width,
               height: image.height,
               markdown: "![](atlas-image:#{image.id})"
             }}

          {:error, reason} ->
            {:error, error(message(reason))}
        end
      after
        File.rm(path)
      end
    else
      {:error, message} -> {:error, error(message)}
    end
  end

  defp message(:not_found), do: "cannot be stored: you do not play or run a campaign"
  defp message(:too_large), do: "is larger than 25 MB"
  defp message(:unsupported_type), do: "is not a JPEG, PNG, WebP, GIF, SVG or AVIF image"
  defp message(:unsafe_svg), do: "is an SVG that refers to external files"
  defp message(:too_many_pixels), do: "has too many pixels"
  defp message(_), do: "could not be read as an image"

  defp error(message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: :url, message: message)
end
