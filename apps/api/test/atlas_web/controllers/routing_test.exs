defmodule AtlasWeb.RoutingTest do
  use AtlasWeb.ConnCase, async: true

  test "API-only mode does not serve SPA pages or LiveView routes", %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")

    for path <- [
          "/",
          "/register",
          "/sign-in",
          "/dashboard",
          "/reset",
          "/password-reset/token",
          "/confirm_new_user/token",
          "/live",
          "/assets/app.js",
          "/admin",
          "/oban",
          "/sign-out"
        ] do
      assert conn |> get(path) |> json_response(404) == %{"errors" => %{"detail" => "Not Found"}}
    end
  end

  test "enabled frontend leaves session JSON, CSRF and security headers intact" do
    conn = frontend_request("/api/session", "application/json")
    refute conn.halted
    conn = get(conn, ~p"/api/session")

    assert %{"user" => nil, "csrfToken" => csrf_token} = json_response(conn, 200)
    assert is_binary(csrf_token) and byte_size(csrf_token) > 0
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "reserved missing routes retain backend JSON 404s with frontend enabled" do
    for prefix <- ~w(.well-known api auth rpc oauth health dev ash_ai) do
      path = "/#{prefix}/missing"
      conn = frontend_request(path, "application/json")
      refute conn.halted
      assert conn |> get(path) |> json_response(404) == %{"errors" => %{"detail" => "Not Found"}}
    end
  end

  test "API routes still reject HTML requests with frontend enabled" do
    conn = frontend_request("/api/session", "text/html")
    refute conn.halted

    assert_error_sent 406, fn ->
      get(conn, ~p"/api/session")
    end
  end

  defp frontend_request(path, accept) do
    opts =
      AtlasWeb.Plugs.Frontend.init(
        serve_frontend: true,
        static_dir: Path.expand("../../fixtures/frontend/public", __DIR__),
        asset_dir: Path.expand("../../fixtures/frontend/retained", __DIR__)
      )

    Plug.Test.conn(:get, path)
    |> put_req_header("accept", accept)
    |> AtlasWeb.Plugs.Frontend.call(opts)
  end
end
