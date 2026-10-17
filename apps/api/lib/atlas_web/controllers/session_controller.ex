defmodule AtlasWeb.SessionController do
  use AtlasWeb, :controller

  def show(conn, _params) do
    respond(conn, conn.assigns[:current_user])
  end

  def delete(conn, _params) do
    conn = AshAuthentication.Phoenix.Controller.clear_session(conn, :atlas)
    Plug.CSRFProtection.delete_csrf_token()
    respond(conn, nil)
  end

  def respond(conn, user) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{
      user: if(user, do: %{id: user.id, email: to_string(user.email)}),
      csrfToken: get_csrf_token()
    })
  end
end
