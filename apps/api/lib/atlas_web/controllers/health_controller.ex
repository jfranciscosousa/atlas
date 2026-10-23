defmodule AtlasWeb.HealthController do
  use AtlasWeb, :controller

  def show(conn, _params) do
    status = if database_ready?(), do: :no_content, else: :service_unavailable

    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, "")
  end

  defp database_ready? do
    match?({:ok, _}, Atlas.Repo.query("SELECT 1", [], timeout: 2_000))
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
