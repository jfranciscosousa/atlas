defmodule AtlasWeb.AuthControllerTest do
  use AtlasWeb.ConnCase, async: true

  @password "a-secure-password"

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "anonymous sessions return a CSRF token and no user", %{conn: conn} do
    conn = get(conn, ~p"/api/session")
    assert %{"user" => nil, "csrfToken" => token} = json_response(conn, 200)
    assert is_binary(token)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "registration, session persistence, logout, and password login", %{conn: conn} do
    registered = register(conn)

    assert %{"user" => %{"id" => id, "email" => "new@example.com"}, "csrfToken" => _} =
             json_response(registered, 200)

    assert is_binary(id)
    assert Ash.get!(Atlas.Accounts.User, id, authorize?: false).display_name == "New User"
    assert get_session(registered, :user_token)
    assert Map.keys(json_response(registered, 200)["user"]) == ["email", "id"]

    home = registered |> recycle() |> get(~p"/api/session")
    assert %{"user" => %{"id" => ^id}} = json_response(home, 200)

    signed_out = home |> recycle() |> delete(~p"/api/session")
    assert %{"user" => nil} = json_response(signed_out, 200)
    refute get_session(signed_out, :user_token)

    replayed = registered |> recycle() |> get(~p"/api/session")
    assert %{"user" => nil} = json_response(replayed, 200)

    signed_in =
      signed_out
      |> recycle()
      |> post(~p"/auth/user/password/sign_in",
        user: %{email: "new@example.com", password: @password}
      )

    assert %{"user" => %{"id" => ^id}} = json_response(signed_in, 200)
    assert get_session(signed_in, :user_token)
  end

  test "invalid credentials do not create a session", %{conn: conn} do
    conn =
      post(conn, ~p"/auth/user/password/sign_in",
        user: %{email: "missing@example.com", password: @password}
      )

    assert %{"error" => "Incorrect email or password"} = json_response(conn, 401)
    refute get_session(conn, :user_token)
  end

  test "registration rejects invalid passwords", %{conn: conn} do
    for {params, field, message} <- [
          {%{password: @password, password_confirmation: "different-password"},
           "password_confirmation", "Passwords must match."},
          {%{password: "short", password_confirmation: "short"}, "password",
           "Use at least 8 characters."}
        ] do
      response =
        post(conn, ~p"/auth/user/password/register",
          user: Map.merge(params, %{email: "invalid@example.com", display_name: "Test User"})
        )

      assert %{"fields" => %{^field => ^message}} = json_response(response, 422)
      refute get_session(response, :user_token)
    end
  end

  test "registration requires a nonblank name of at most 100 characters", %{conn: conn} do
    for input <- [
          %{},
          %{display_name: nil},
          %{display_name: ""},
          %{display_name: "   "},
          %{display_name: String.duplicate("a", 101)}
        ] do
      response =
        post(conn, ~p"/auth/user/password/register",
          user:
            Map.merge(
              %{
                email: "invalid@example.com",
                password: @password,
                password_confirmation: @password
              },
              input
            )
        )

      assert %{"fields" => %{"display_name" => message}} = json_response(response, 422)
      assert message in ["Display name is required.", "Use a name between 1 and 100 characters."]
      refute get_session(response, :user_token)
    end
  end

  test "duplicate registration does not authenticate the requester", %{conn: conn} do
    assert register(conn).status == 200
    duplicate = register(conn)

    assert %{
             "fields" => %{
               "email" =>
                 "An account with this email already exists. Sign in or reset your password."
             }
           } = json_response(duplicate, 422)

    refute get_session(duplicate, :user_token)
  end

  test "registration rejects invalid email addresses", %{conn: conn} do
    response =
      post(conn, ~p"/auth/user/password/register",
        user: %{
          email: "not-an-email",
          display_name: "Test User",
          password: @password,
          password_confirmation: @password
        }
      )

    assert %{"fields" => %{"email" => "Enter a valid email address."}} =
             json_response(response, 422)

    refute get_session(response, :user_token)
  end

  test "password reset requests do not reveal whether an account exists", %{conn: conn} do
    assert register(conn).status == 200

    for email <- ["new@example.com", "missing@example.com"] do
      response = post(conn, ~p"/auth/user/password/reset_request", user: %{email: email})
      assert %{"user" => nil, "csrfToken" => token} = json_response(response, 200)
      assert is_binary(token)
      refute get_session(response, :user_token)
    end

    assert is_binary(email_token("Reset your password", "password-reset"))
    refute_received {:email, %Swoosh.Email{subject: "Reset your password"}}
  end

  test "password reset revokes old sessions and the reset token", %{conn: conn} do
    registered = register(conn)
    %{"user" => %{"id" => id}} = json_response(registered, 200)

    assert post(conn, ~p"/auth/user/password/reset_request", user: %{email: "new@example.com"}).status ==
             200

    token = email_token("Reset your password", "password-reset")

    params = %{
      reset_token: token,
      password: "replacement-password",
      password_confirmation: "replacement-password"
    }

    reset = post(conn, ~p"/auth/user/password/reset", user: params)
    assert %{"user" => nil, "csrfToken" => csrf_token} = json_response(reset, 200)
    refute get_session(reset, :user_token)

    assert %{"user" => nil} =
             reset |> recycle() |> get(~p"/api/session") |> json_response(200)

    replay = post(conn, ~p"/auth/user/password/reset", user: params)

    assert %{"error" => "This password reset link is invalid or has expired. Request a new link."} =
             json_response(replay, 422)

    old_session = registered |> recycle() |> get(~p"/api/session")
    assert %{"user" => nil} = json_response(old_session, 200)

    old_password =
      post(conn, ~p"/auth/user/password/sign_in",
        user: %{email: "new@example.com", password: @password}
      )

    assert old_password.status == 401

    new_password =
      reset
      |> csrf_request(csrf_token)
      |> post(~p"/auth/user/password/sign_in",
        user: %{email: "new@example.com", password: "replacement-password"}
      )

    assert %{"user" => %{"id" => ^id}} = json_response(new_password, 200)

    assert %{"user" => %{"id" => ^id}} =
             new_password |> recycle() |> get(~p"/api/session") |> json_response(200)
  end

  test "reset password validation preserves the token for a valid submission", %{conn: conn} do
    assert register(conn).status == 200

    assert post(conn, ~p"/auth/user/password/reset_request", user: %{email: "new@example.com"}).status ==
             200

    token = email_token("Reset your password", "password-reset")

    for {password, confirmation, field} <- [
          {"short", "short", "password"},
          {"replacement-password", "different-password", "password_confirmation"}
        ] do
      response =
        post(conn, ~p"/auth/user/password/reset",
          user: %{reset_token: token, password: password, password_confirmation: confirmation}
        )

      assert %{"fields" => %{^field => _}} = json_response(response, 422)
      refute get_session(response, :user_token)
    end

    response =
      post(conn, ~p"/auth/user/password/reset",
        user: %{
          reset_token: token,
          password: "replacement-password",
          password_confirmation: "replacement-password"
        }
      )

    assert response.status == 200
  end

  test "email confirmation requires a POST and confirms only once", %{conn: conn} do
    registered = register(conn)
    %{"user" => %{"id" => id}} = json_response(registered, 200)
    token = email_token("Confirm your email address", "confirm_new_user")

    assert conn |> get("/auth/user/confirm_new_user?confirm=" <> token) |> json_response(404)

    user = Ash.get!(Atlas.Accounts.User, id, authorize?: false)
    assert is_nil(user.confirmed_at)

    confirmed = post(conn, ~p"/auth/user/confirm_new_user", user: %{confirm: token})
    assert %{"user" => %{"id" => ^id}} = json_response(confirmed, 200)
    assert get_session(confirmed, :user_token)
    user = Ash.get!(Atlas.Accounts.User, id, authorize?: false)
    refute is_nil(user.confirmed_at)

    replay = post(conn, ~p"/auth/user/confirm_new_user", user: %{confirm: token})

    assert %{"error" => "This confirmation link is invalid or has expired."} =
             json_response(replay, 422)

    refute get_session(replay, :user_token)
  end

  test "invalid reset and confirmation links do not authenticate users", %{conn: conn} do
    reset =
      post(conn, ~p"/auth/user/password/reset",
        user: %{reset_token: "invalid", password: @password, password_confirmation: @password}
      )

    assert reset.status == 422
    refute get_session(reset, :user_token)

    confirmed = post(conn, ~p"/auth/user/confirm_new_user", user: %{confirm: "invalid"})
    assert confirmed.status == 422
    refute get_session(confirmed, :user_token)
  end

  test "authentication and logout require CSRF protection", %{conn: conn} do
    for {method, path} <- [
          {:post, ~p"/auth/user/password/register"},
          {:post, ~p"/auth/user/password/sign_in"},
          {:post, ~p"/auth/user/password/reset_request"},
          {:post, ~p"/auth/user/password/reset"},
          {:post, ~p"/auth/user/confirm_new_user"},
          {:post, ~p"/rpc/run"},
          {:post, ~p"/rpc/validate"},
          {:delete, ~p"/api/session"}
        ] do
      assert_error_sent 403, fn ->
        conn
        |> put_private(:plug_skip_csrf_protection, false)
        |> dispatch(@endpoint, method, path, %{})
      end
    end
  end

  test "a session CSRF token permits registration", %{conn: conn} do
    session = get(conn, ~p"/api/session")
    token = json_response(session, 200)["csrfToken"]

    registered =
      session
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", token)
      |> register()

    assert %{"user" => %{"email" => "new@example.com"}} = json_response(registered, 200)
  end

  test "logout returns a valid CSRF token for the next login", %{conn: conn} do
    anonymous = get(conn, ~p"/api/session")
    token = json_response(anonymous, 200)["csrfToken"]
    registered = anonymous |> csrf_request(token) |> register()
    token = json_response(registered, 200)["csrfToken"]

    signed_out = registered |> csrf_request(token) |> delete(~p"/api/session")
    token = json_response(signed_out, 200)["csrfToken"]

    signed_in =
      signed_out
      |> csrf_request(token)
      |> post(~p"/auth/user/password/sign_in",
        user: %{email: "new@example.com", password: @password}
      )

    assert %{"user" => %{"email" => "new@example.com"}} = json_response(signed_in, 200)
  end

  defp email_token(subject, path) do
    assert_receive {:email, %Swoosh.Email{subject: ^subject, html_body: body}}
    [_, token] = Regex.run(~r{href="http://localhost:3000/#{path}/([^"]+)"}, body)
    URI.decode_www_form(token)
  end

  defp csrf_request(conn, token) do
    conn
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
  end

  defp register(conn) do
    post(conn, ~p"/auth/user/password/register",
      user: %{
        email: "new@example.com",
        display_name: "  New User  ",
        password: @password,
        password_confirmation: @password
      }
    )
  end
end
