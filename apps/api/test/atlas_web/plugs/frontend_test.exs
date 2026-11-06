defmodule AtlasWeb.Plugs.FrontendTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AtlasWeb.Plugs.Frontend

  @fixtures Path.expand("../../fixtures/frontend", __DIR__)
  @reserved ~w(.well-known api auth rpc mcp oauth socket health dev ash_ai)

  defp options(overrides \\ []) do
    Frontend.init(
      Keyword.merge(
        [
          serve_frontend: true,
          static_dir: Path.join(@fixtures, "public"),
          asset_dir: Path.join(@fixtures, "retained")
        ],
        overrides
      )
    )
  end

  defp request(path, accept \\ "text/html", method \\ :get, overrides \\ []) do
    conn(method, path)
    |> put_req_header("accept", accept)
    |> Frontend.call(options(overrides))
  end

  test "disabled delivery passes every request through, even existing static files" do
    for path <- [
          "/",
          "/index.html",
          "/favicon.ico",
          "/assets/app-current.js",
          "/assets/app-old.js"
        ] do
      original = conn(:get, path) |> put_req_header("accept", "*/*")
      assert Frontend.call(original, options(serve_frontend: false)) == original
    end
  end

  test "GET and HEAD are the only frontend methods" do
    for method <- [:post, :put, :patch, :delete, :options] do
      conn = request("/assets/app-current.js", "*/*", method)
      refute conn.halted
      assert conn.status == nil
    end
  end

  test "every backend namespace and descendant passes through, regardless of Accept" do
    for prefix <- @reserved,
        suffix <- ["", "/", "/missing", "/missing.js"],
        accept <- ["text/html", "*/*", "application/json"],
        method <- [:get, :head] do
      original = conn(method, "/" <> prefix <> suffix) |> put_req_header("accept", accept)
      assert Frontend.call(original, options()) == original
    end

    refute request("/%61pi/session").halted
    refute request("/%2ewell-known/oauth-authorization-server").halted
    assert request("/apiary").status == 200
  end

  test "SPA pages accept HTML, text wildcards, curl wildcards, and missing Accept" do
    for path <- ["/", "/sign-in", "/campaigns/123/world", "/sign-in?next=%2Fdashboard"],
        accept <- [
          "text/html",
          "text/html; charset=utf-8",
          "text/*",
          "*/*",
          "application/json, text/html;q=0.2",
          "application/json, */*;q=0.1"
        ] do
      conn = request(path, accept)
      assert conn.status == 200
      assert conn.halted
      assert conn.resp_body =~ "Atlas fixture"
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert get_resp_header(conn, "vary") == ["Accept"]
    end

    assert conn(:get, "/dashboard") |> Frontend.call(options()) |> Map.fetch!(:status) == 200
  end

  test "signed-token application pages are not mistaken for missing assets" do
    for page <- ~w(confirm_new_user password-reset claim join), method <- [:get, :head] do
      conn = request("/#{page}/eyJhbGciOiJIUzI1NiJ9.payload.signature", "text/html", method)
      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
    end
  end

  test "SPA negotiation respects exclusions, specificity, and non-HTML clients" do
    for accept <- [
          "application/json",
          "text/plain",
          "text/html;q=0",
          "text/html;q=0, */*;q=1",
          "text/*;q=0, */*;q=1",
          "text/html;q=bogus, */*",
          "text/html;q=1.5",
          "not a media type"
        ] do
      conn = request("/dashboard", accept)
      assert conn.status == 404, "accepted #{accept}"
      refute conn.resp_body =~ "Atlas fixture"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert get_resp_header(conn, "vary") == ["Accept"]
      assert Jason.decode!(conn.resp_body) == %{"errors" => %{"detail" => "Not Found"}}
    end

    assert request("/dashboard", "text/*;q=0, text/html;q=0.5").status == 200
  end

  test "packaged and retained assets are immutable, and packaged assets win" do
    for {path, body} <- [
          {"/assets/app-current.js", "packaged current"},
          {"/assets/app-old.js", "retained old"},
          {"/assets/shared.js", "packaged wins"},
          {"/assets/app-current.css", "color: black"},
          {"/assets/fonts/current.woff2", "packaged font"},
          {"/assets/fonts/old.woff2", "retained font"}
        ] do
      conn = request(path, "*/*")
      assert conn.status == 200
      assert conn.resp_body =~ body
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    assert request("/assets/app-current.js").resp_body ==
             File.read!(Path.join(@fixtures, "public/assets/app-current.js"))

    assert get_resp_header(request("/assets/app-current.css"), "content-type") == [
             "text/css; charset=utf-8"
           ]
  end

  test "root public outputs and HTML only come from the packaged image" do
    assert request("/favicon.ico", "*/*").resp_body == "packaged favicon fixture\n"
    assert request("/robots.txt", "*/*").resp_body =~ "User-agent"
    assert request("/index.html").resp_body =~ "Atlas fixture"
    assert get_resp_header(request("/index.html"), "cache-control") == ["no-cache"]
    assert get_resp_header(request("/favicon.ico"), "cache-control") == ["no-cache"]
    assert request("/retained-only.svg").status == 404
    assert request("/assets/index.html").status == 404
    assert request("/assets/old.html").status == 404
    assert request("/assets/old.xhtml").status == 404
    assert request("/assets/page.html").status == 200
    assert get_resp_header(request("/assets/page.html"), "cache-control") == ["no-cache"]
    assert request("/assets/retained-only.svg").status == 200
  end

  test "missing files and all missing asset paths stay real 404s, never the SPA" do
    for path <- [
          "/assets",
          "/assets/",
          "/assets/no-extension",
          "/assets/missing.js",
          "/assets/missing.css",
          "/missing.ico",
          "/missing.svg",
          "/missing.js.map",
          "/missing.html",
          "/directory.with-dot/page"
        ] do
      for method <- [:get, :head] do
        conn = request(path, "text/html", method)
        assert conn.status == 404
        assert conn.halted
        refute conn.resp_body =~ "Atlas fixture"
        assert get_resp_header(conn, "cache-control") == ["no-store"]
      end
    end
  end

  test "HEAD returns GET headers and content length, without a response body" do
    for path <- [
          "/",
          "/dashboard",
          "/index.html",
          "/favicon.ico",
          "/assets/app-current.js",
          "/assets/app-old.js"
        ] do
      get = request(path)
      head = request(path, "text/html", :head)
      assert head.status == 200
      assert head.resp_body == ""
      assert head.resp_headers == get.resp_headers

      assert get_resp_header(head, "content-length") == [
               Integer.to_string(byte_size(get.resp_body))
             ]
    end

    assert request("/dashboard", "application/json", :head).status == 404
    missing_get = request("/assets/missing.js", "*/*")
    missing_head = request("/assets/missing.js", "*/*", :head)
    assert missing_head.resp_body == ""
    assert missing_head.resp_headers == missing_get.resp_headers
  end

  test "safe headers do not add CSP or session cookies and preserve existing Vary" do
    for path <- ["/", "/assets/app-current.js", "/missing.svg"] do
      conn = request(path)
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
      assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
      assert get_resp_header(conn, "content-security-policy") == []
      assert get_resp_header(conn, "set-cookie") == []
    end

    conn =
      conn(:get, "/")
      |> put_resp_header("vary", "Origin")
      |> Frontend.call(options())

    assert get_resp_header(conn, "vary") == ["Origin, Accept"]
  end

  test "unsafe paths cannot expose hidden files or escape either root" do
    for path <- [
          "/.private",
          "/%2eprivate",
          "/assets/../index.html",
          "/assets/%2e%2e/index.html",
          "/assets/%2e%2e%2findex.html",
          "/assets/..%5cindex.html",
          "/assets/%00.js",
          "/assets/%FF.js"
        ] do
      assert request(path).status == 404
    end
  end

  @tag :tmp_dir
  test "symlink files and directories are never public", %{tmp_dir: root} do
    File.write!(Path.join(root, "index.html"), "local fixture")
    File.mkdir!(Path.join(root, "assets"))
    File.ln_s!(Path.join(@fixtures, "public/index.html"), Path.join(root, "leak.html"))

    File.ln_s!(
      Path.join(@fixtures, "public/assets/app-current.js"),
      Path.join(root, "assets/leak.js")
    )

    File.ln_s!(Path.join(@fixtures, "public/assets"), Path.join(root, "assets/link"))

    for path <- ["/leak.html", "/assets/leak.js", "/assets/link/app-current.js"] do
      assert request(path, "text/html", :get, static_dir: root, asset_dir: nil).status == 404
    end

    assert request("/assets/leak.js", "*/*", :get,
             static_dir: Path.join(root, "missing"),
             asset_dir: Path.join(root, "assets")
           ).status == 404
  end

  test "missing static roots fail closed, and retained assets do not supply the SPA" do
    assert request("/", "text/html", :get, static_dir: Path.join(@fixtures, "missing")).status ==
             404

    assert request("/assets/app-current.js", "*/*", :get, asset_dir: nil).status == 200

    for invalid_root <- [nil, "", "relative/path"] do
      assert request("/assets/app-old.js", "*/*", :get, asset_dir: invalid_root).status == 404
    end
  end
end
