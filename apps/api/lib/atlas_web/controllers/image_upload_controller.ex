defmodule AtlasWeb.ImageUploadController do
  use AtlasWeb, :controller

  alias Atlas.Images.Uploads

  def create(conn, %{
        "parent" => parent,
        "parent_id" => parent_id,
        "section" => section,
        "file" => %Plug.Upload{path: path}
      }) do
    case conn.assigns[:current_user] do
      nil -> error(conn, :unauthorized, "Sign in to continue.")
      user -> respond(conn, Uploads.upload_image(user, parent, parent_id, section, path))
    end
  end

  def create(conn, _params), do: error(conn, :unprocessable_entity, "Choose an image file.")

  defp respond(conn, {:ok, image}) do
    conn
    |> put_status(:created)
    |> json(%{
      id: image.id,
      width: image.width,
      height: image.height,
      animated: image.animated
    })
  end

  defp respond(conn, {:error, :not_found}), do: error(conn, :not_found, "Not found.")

  defp respond(conn, {:error, :too_large}),
    do: error(conn, :request_entity_too_large, "The image is larger than 25 MB.")

  defp respond(conn, {:error, :unsupported_type}),
    do: error(conn, :unsupported_media_type, "Use a JPEG, PNG, WebP, GIF, SVG or AVIF image.")

  defp respond(conn, {:error, :unsafe_svg}),
    do: error(conn, :unprocessable_entity, "The SVG refers to external files.")

  defp respond(conn, {:error, :too_many_pixels}),
    do: error(conn, :unprocessable_entity, "The image has too many pixels.")

  defp respond(conn, {:error, reason}) when reason in [:unreadable, :timeout],
    do: error(conn, :unprocessable_entity, "The image could not be read.")

  defp respond(conn, {:error, _other}), do: error(conn, :internal_server_error, "Upload failed.")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
