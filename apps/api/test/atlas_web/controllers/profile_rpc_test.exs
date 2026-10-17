defmodule AtlasWeb.ProfileRpcTest do
  use AtlasWeb.ConnCase, async: true

  @fields ["id", "email", "displayName", "avatar"]
  @avatar "data:image/png;base64," <>
            Base.encode64(<<137, "PNG\r\n", 26, 10, "test-image">>)

  test "users can read and update their profile and remove their avatar", %{conn: conn} do
    user = register(conn, "owner@example.com")
    id = json_response(user, 200)["user"]["id"]

    assert %{
             "success" => true,
             "data" => %{"id" => ^id, "displayName" => "Test User", "avatar" => nil}
           } =
             rpc(user, "get_profile", %{fields: @fields})

    assert %{"success" => true, "data" => %{"displayName" => "Jane Doe", "avatar" => @avatar}} =
             rpc(user, "update_profile", %{
               identity: id,
               input: %{displayName: "  Jane Doe  ", avatar: @avatar},
               fields: @fields
             })

    assert %{"data" => %{"displayName" => "Jane Doe", "avatar" => @avatar}} =
             rpc(user, "get_profile", %{fields: @fields})

    assert %{"success" => true, "data" => %{"displayName" => "Jane Doe", "avatar" => nil}} =
             rpc(user, "update_profile", %{
               identity: id,
               input: %{avatar: nil},
               fields: @fields
             })
  end

  test "users cannot read or update another user's profile", %{conn: conn} do
    owner = register(conn, "owner@example.com")
    other = register(conn, "other@example.com")
    owner_id = json_response(owner, 200)["user"]["id"]
    other_id = json_response(other, 200)["user"]["id"]

    assert %{"success" => true, "data" => %{"id" => ^other_id}} =
             rpc(other, "get_profile", %{fields: @fields})

    assert %{"success" => false} =
             rpc(other, "update_profile", %{
               identity: owner_id,
               input: %{displayName: "Not the owner"},
               fields: @fields
             })

    assert %{"data" => %{"displayName" => "Test User"}} =
             rpc(owner, "get_profile", %{fields: @fields})
  end

  test "anonymous profile requests require authentication", %{conn: conn} do
    user = register(conn, "owner@example.com")
    id = json_response(user, 200)["user"]["id"]

    assert %{"error" => "Sign in to continue."} =
             rpc(conn, "get_profile", %{fields: @fields}, 401)

    assert %{"error" => "Sign in to continue."} =
             rpc(conn, "update_profile", %{identity: id, input: %{displayName: "Jane"}}, 401)
  end

  test "profile updates require CSRF protection", %{conn: conn} do
    user = register(conn, "owner@example.com")
    id = json_response(user, 200)["user"]["id"]

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      user
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(~p"/rpc/run", %{
        action: "update_profile",
        identity: id,
        input: %{displayName: "Jane"}
      })
    end
  end

  test "invalid names and avatars do not change the profile", %{conn: conn} do
    user = register(conn, "owner@example.com")
    id = json_response(user, 200)["user"]["id"]

    for input <- [
          %{displayName: nil},
          %{displayName: ""},
          %{displayName: "   "},
          %{displayName: String.duplicate("a", 101)},
          %{avatar: "https://example.com/avatar.png"},
          %{avatar: "data:image/svg+xml;base64," <> Base.encode64("<svg />")},
          %{avatar: "data:image/png;base64,not-base64!"},
          %{avatar: "data:image/png;base64," <> Base.encode64("not a PNG")},
          %{avatar: "data:image/jpeg;base64," <> Base.encode64(<<137, "PNG\r\n", 26, 10>>)},
          %{
            avatar:
              "data:image/png;base64," <>
                Base.encode64(<<137, "PNG\r\n", 26, 10>> <> String.duplicate("a", 512 * 1024))
          }
        ] do
      assert %{"success" => false, "errors" => [_ | _]} =
               rpc(user, "update_profile", %{identity: id, input: input, fields: @fields})
    end

    assert %{"data" => %{"displayName" => "Test User", "avatar" => nil}} =
             rpc(user, "get_profile", %{fields: @fields})
  end

  test "JPEG and WebP avatars are accepted", %{conn: conn} do
    user = register(conn, "owner@example.com")
    id = json_response(user, 200)["user"]["id"]

    for {type, bytes} <- [
          {"jpeg", <<255, 216, 255, "test-image">>},
          {"webp", <<"RIFF", 0, 0, 0, 0, "WEBPtest-image">>}
        ] do
      avatar = "data:image/#{type};base64," <> Base.encode64(bytes)

      assert %{"success" => true, "data" => %{"avatar" => ^avatar}} =
               rpc(user, "update_profile", %{
                 identity: id,
                 input: %{avatar: avatar},
                 fields: @fields
               })
    end
  end

  @tag capture_log: true
  test "profile updates cannot change account credentials or IDs", %{conn: conn} do
    user = register(conn, "owner@example.com")
    id = json_response(user, 200)["user"]["id"]

    for input <- [
          %{email: "changed@example.com"},
          %{id: Ecto.UUID.generate()},
          %{hashedPassword: "bad"}
        ] do
      assert %{"success" => false} =
               rpc(user, "update_profile", %{identity: id, input: input, fields: @fields})
    end

    assert %{"data" => %{"id" => ^id, "email" => "owner@example.com"}} =
             rpc(user, "get_profile", %{fields: @fields})
  end

  defp register(conn, email) do
    response =
      post(conn, ~p"/auth/user/password/register",
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

  defp rpc(conn, action, params, status \\ 200) do
    session = conn |> recycle() |> get(~p"/api/session")
    token = json_response(session, 200)["csrfToken"]

    session
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
    |> post(~p"/rpc/run", Map.put(params, :action, action))
    |> json_response(status)
  end
end
