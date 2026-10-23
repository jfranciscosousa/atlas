defmodule AtlasWeb.HealthControllerTest do
  use AtlasWeb.ConnCase, async: true

  test "health is public, accepts HTML, and returns no content", %{conn: conn} do
    conn = conn |> put_req_header("accept", "text/html") |> get(~p"/health")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "health returns no content and service unavailable when the database cannot be used", %{
    conn: conn
  } do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        send(parent, {:health_response, get(conn, ~p"/health")})
      end)

    assert_receive {:health_response, conn}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert response(conn, 503) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end
