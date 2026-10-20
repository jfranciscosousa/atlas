defmodule AtlasWeb.RpcHelpers do
  @moduledoc false
  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint AtlasWeb.Endpoint

  def register(conn, email) do
    response =
      post(conn, "/auth/user/password/register",
        user: %{
          email: email,
          display_name: "Test User",
          password: "a-secure-password",
          password_confirmation: "a-secure-password"
        }
      )

    assert %{"user" => %{"id" => _}} = json_response(response, 200)
    response
  end

  def csrf(conn) do
    session = conn |> recycle() |> get("/api/session")
    {session, json_response(session, 200)["csrfToken"]}
  end

  def rpc(conn, action, params, status \\ 200) do
    {session, token} = csrf(conn)

    session
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
    |> post("/rpc/run", Map.put(params, :action, action))
    |> json_response(status)
  end

  def upload(conn, campaign_id, section, binary, status \\ 201),
    do: upload_to(conn, "campaigns", campaign_id, section, binary, status)

  def upload_to(conn, parent, parent_id, section, binary, status \\ 201) do
    path = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}")
    File.write!(path, binary)
    {session, token} = csrf(conn)

    session
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
    |> put_req_header("accept", "application/json")
    |> post("/api/#{parent}/#{parent_id}/sections/#{section}/images", %{
      "file" => %Plug.Upload{path: path, filename: "x", content_type: "image/png"}
    })
    |> json_response(status)
  end
end
