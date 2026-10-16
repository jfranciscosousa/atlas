defmodule LemonadeStandWeb.RoutingTest do
  use LemonadeStandWeb.ConnCase, async: true

  test "the API does not serve SPA pages or LiveView routes", %{conn: conn} do
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

  test "API routes reject HTML requests", %{conn: conn} do
    assert_error_sent 406, fn ->
      conn |> put_req_header("accept", "text/html") |> get(~p"/api/session")
    end
  end
end
