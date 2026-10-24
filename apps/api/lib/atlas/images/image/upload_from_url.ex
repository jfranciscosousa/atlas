defmodule Atlas.Images.Image.UploadFromUrl do
  @moduledoc """
  Downloads an image from a public URL and stores it like an upload from the web app: the same
  rights check, size limit, type check and WebP conversion. `store/3` is shared with the
  base64 upload.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Images.{Fetch, Uploads}

  @impl true
  def run(input, _opts, %{actor: actor}) do
    with {:ok, path} <- Fetch.download(input.arguments.url) do
      store(actor, path, :url)
    else
      {:error, message} -> {:error, error(:url, message)}
    end
  end

  @doc "Stores the image file at `path` for the actor, then deletes the file."
  def store(actor, path, field) do
    case Uploads.upload_image(actor, path) do
      {:ok, image} ->
        {:ok,
         %{
           id: image.id,
           width: image.width,
           height: image.height,
           block: %{type: "image", props: %{url: "atlas-image:#{image.id}"}}
         }}

      {:error, reason} ->
        {:error, error(field, message(reason))}
    end
  after
    File.rm(path)
  end

  defp message(:not_found), do: "cannot be stored: you do not play or run a campaign"
  defp message(:too_large), do: "is larger than 25 MB"
  defp message(:unsupported_type), do: "is not a JPEG, PNG, WebP, GIF, SVG or AVIF image"
  defp message(:unsafe_svg), do: "is an SVG that refers to external files"
  defp message(:too_many_pixels), do: "has too many pixels"
  defp message(_), do: "could not be read as an image"

  def error(field, message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: field, message: message)
end
