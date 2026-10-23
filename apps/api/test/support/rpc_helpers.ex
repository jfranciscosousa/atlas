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

    assert %{"user" => nil} = json_response(response, 200)
    confirm_email(conn)
  end

  @doc "Confirms the account from the email it was sent. This signs the person in."
  def confirm_email(conn) do
    assert_receive {:email, %Swoosh.Email{subject: "Confirm your email address", html_body: body}}
    [_, token] = Regex.run(~r{href="http://localhost:3000/confirm_new_user/([^"]+)"}, body)

    response =
      post(conn, "/auth/user/confirm_new_user", user: %{confirm: URI.decode_www_form(token)})

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

  def upload(conn, binary, status \\ 201) do
    path = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}")
    File.write!(path, binary)
    {session, token} = csrf(conn)

    session
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
    |> put_req_header("accept", "application/json")
    |> post("/api/images", %{
      "file" => %Plug.Upload{path: path, filename: "x", content_type: "image/png"}
    })
    |> json_response(status)
  end
end
