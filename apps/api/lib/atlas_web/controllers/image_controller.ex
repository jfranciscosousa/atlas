defmodule AtlasWeb.ImageController do
  use AtlasWeb, :controller

  def show(conn, %{"token" => token}) do
    case Atlas.Storage.LocalDisk.read_signed(token) do
      {:ok, body} ->
        conn
        |> put_resp_content_type("image/webp")
        |> put_resp_header("cache-control", "private, max-age=#{Atlas.Storage.ttl_seconds()}")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, body)

      :error ->
        send_resp(conn, 404, "")
    end
  end
end
