defmodule AtlasWeb.HealthControllerTest do
  use AtlasWeb.ConnCase, async: false

  alias AtlasWeb.HealthController

  defmodule ReadOnlyRepo do
    def query(sql, params, opts) do
      send(self(), {:health_query, sql, params, opts})
      Process.get(:health_query_result)
    end
  end

  setup do
    previous = Application.get_env(:atlas, :serve_frontend)
    Application.put_env(:atlas, :serve_frontend, false)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:atlas, :serve_frontend),
        else: Application.put_env(:atlas, :serve_frontend, previous)
    end)

    root = Path.join(System.tmp_dir!(), "atlas-health-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "assets"))
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(root, "index.html"), index())
    File.write!(Path.join(root, "assets/app-123.js"), "export {};")
    File.write!(Path.join(root, "assets/app-123.css"), "body{}")
    %{root: root}
  end

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
        Atlas.Repo.put_dynamic_repo(:unavailable_health_repo)
        send(parent, {:health_response, get(conn, ~p"/health")})
      end)

    assert_receive {:health_response, conn}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert response(conn, 503) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "API-only mode ignores schema and static assets", %{root: root} do
    Process.put(:health_query_result, {:ok, %{rows: [[1]]}})
    File.rm!(Path.join(root, "index.html"))
    assert HealthController.ready?(false, ReadOnlyRepo, root)
    assert_received {:health_query, "SELECT 1", [], opts}
    assert opts[:timeout] == 2_000
    assert opts[:log] == false
    refute_received {:health_query, _, _, _}
  end

  test "native mode requires both applied schema and own packaged assets", %{root: root} do
    {:ok, versions} = Atlas.SchemaReadiness.packaged_versions()
    rows = Enum.map(versions, &[&1])
    Process.put(:health_query_result, {:ok, %{rows: rows ++ [[9_223_372_036_854_775_807]]}})
    assert HealthController.ready?(true, ReadOnlyRepo, root)
    assert_received {:health_query, "SELECT version FROM schema_migrations", [], _}

    Process.put(:health_query_result, {:ok, %{rows: []}})
    refute HealthController.ready?(true, ReadOnlyRepo, root)

    Process.put(:health_query_result, {:ok, %{rows: rows}})
    File.rm!(Path.join(root, "assets/app-123.js"))
    refute HealthController.ready?(true, ReadOnlyRepo, root)

    Process.put(:health_query_result, {:error, "private connection details"})
    refute HealthController.ready?(true, ReadOnlyRepo, root)
  end

  test "native HTTP response is generic when schema cannot be read", %{conn: conn} do
    Application.put_env(:atlas, :serve_frontend, true)
    previous_repo = Atlas.Repo.put_dynamic_repo(:unavailable_native_health_repo)

    conn =
      try do
        get(conn, ~p"/health")
      after
        Atlas.Repo.put_dynamic_repo(previous_repo)
      end

    assert response(conn, 503) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "complete index accepts script src and TanStack inline module import", %{root: root} do
    assert HealthController.frontend_ready?(root)

    File.write!(
      Path.join(root, "index.html"),
      index(~s|<script type="module">import("/assets/app-123.js")</script>|)
    )

    assert HealthController.frontend_ready?(root)
  end

  test "missing, empty, placeholder and oversized index fail", %{root: root} do
    for html <- ["", "<html>placeholder</html>", String.duplicate("x", 256 * 1024 + 1)] do
      File.write!(Path.join(root, "index.html"), html)
      refute HealthController.frontend_ready?(root)
    end

    File.rm!(Path.join(root, "index.html"))
    refute HealthController.frontend_ready?(root)
  end

  test "every referenced local JS/CSS must exist and be nonempty", %{root: root} do
    File.write!(Path.join(root, "assets/app-123.css"), "")
    refute HealthController.frontend_ready?(root)
    File.write!(Path.join(root, "assets/app-123.css"), "body{}")

    File.write!(
      Path.join(root, "index.html"),
      index()
      |> String.replace(
        "</head>",
        ~s(<link rel="modulepreload" href="/assets/missing.js"></head>)
      )
    )

    refute HealthController.frontend_ready?(root)
  end

  test "remote assets cannot replace a local JS and CSS build", %{root: root} do
    File.write!(
      Path.join(root, "index.html"),
      String.replace(index(), "/assets/", "https://example.test/assets/")
    )

    refute HealthController.frontend_ready?(root)
  end

  test "query strings, relative asset URLs and additional remote references are supported", %{
    root: root
  } do
    html =
      index()
      |> String.replace("/assets/", "assets/")
      |> String.replace("app-123.js", "app-123.js?v=1")
      |> String.replace(
        "</head>",
        ~s(<script src="https://example.test/remote.js"></script></head>)
      )

    File.write!(Path.join(root, "index.html"), html)
    assert HealthController.frontend_ready?(root)
  end

  test "traversal, encoded paths and non-asset local paths fail closed", %{root: root} do
    for path <- [
          "/assets/../app.js",
          "/assets/%2e%2e/app.js",
          "/assets/nested/../../app.js",
          "/app.js",
          "/assets/a%2fb.js",
          "/assets/a\\b.js"
        ] do
      File.write!(
        Path.join(root, "index.html"),
        index() |> String.replace("/assets/app-123.js", path)
      )

      refute HealthController.frontend_ready?(root)
    end
  end

  test "symlink index, asset, directory and root are rejected", %{root: root} do
    File.rename!(Path.join(root, "index.html"), Path.join(root, "real.html"))
    File.ln_s!("real.html", Path.join(root, "index.html"))
    refute HealthController.frontend_ready?(root)
    File.rm!(Path.join(root, "index.html"))
    File.rename!(Path.join(root, "real.html"), Path.join(root, "index.html"))

    File.rename!(Path.join(root, "assets/app-123.js"), Path.join(root, "real.js"))
    File.ln_s!("../real.js", Path.join(root, "assets/app-123.js"))
    refute HealthController.frontend_ready?(root)
    File.rm!(Path.join(root, "assets/app-123.js"))
    File.rename!(Path.join(root, "real.js"), Path.join(root, "assets/app-123.js"))

    File.rename!(Path.join(root, "assets"), Path.join(root, "real-assets"))
    File.ln_s!("real-assets", Path.join(root, "assets"))
    refute HealthController.frontend_ready?(root)

    link = root <> "-symlink"
    File.ln_s!(root, link)
    on_exit(fn -> File.rm!(link) end)
    refute HealthController.frontend_ready?(link)
  end

  test "oversized assets are rejected using metadata, without reading bundles", %{root: root} do
    asset = Path.join(root, "assets/app-123.js")

    File.open!(asset, [:write, :binary], fn file ->
      {:ok, _} = :file.position(file, 64 * 1024 * 1024)
      :ok = IO.binwrite(file, "x")
    end)

    refute HealthController.frontend_ready?(root)
  end

  test "overlong asset paths and excessive nesting fail closed", %{root: root} do
    for path <- [
          "/assets/" <> String.duplicate("a", 513) <> ".js",
          "/assets/a/b/c/d/e/f/g/h/app.js"
        ] do
      File.write!(
        Path.join(root, "index.html"),
        String.replace(index(), "/assets/app-123.js", path)
      )

      refute HealthController.frontend_ready?(root)
    end
  end

  test "static inspection limits reference count and rejects directory assets", %{root: root} do
    tags = Enum.map_join(1..257, fn n -> ~s(<link href="/assets/#{n}.css">) end)

    File.write!(
      Path.join(root, "index.html"),
      String.replace(index(), "</head>", tags <> "</head>")
    )

    refute HealthController.frontend_ready?(root)

    File.write!(Path.join(root, "index.html"), index())
    File.rm!(Path.join(root, "assets/app-123.js"))
    File.mkdir!(Path.join(root, "assets/app-123.js"))
    refute HealthController.frontend_ready?(root)
  end

  defp index(script \\ ~s(<script type="module" src="/assets/app-123.js"></script>)) do
    """
    <!DOCTYPE html><html><head>
    <link rel="stylesheet" href="/assets/app-123.css">
    </head><body>#{script}</body></html>
    """
  end
end
