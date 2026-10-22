defmodule AtlasWeb.McpOAuthTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers

  alias Atlas.Fixtures

  @redirect "https://claude.ai/api/mcp/auth_callback"
  @verifier String.duplicate("v", 50)

  defp challenge(verifier \\ @verifier),
    do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

  defp register_client(conn) do
    body = %{client_name: "Claude", redirect_uris: [@redirect]}
    response = conn |> post("/oauth/register", body) |> json_response(201)
    response["client_id"]
  end

  defp authorize_params(client_id, extra \\ %{}) do
    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => @redirect,
        "code_challenge" => challenge(),
        "code_challenge_method" => "S256",
        "state" => "xyz"
      },
      extra
    )
  end

  # The consent page posts the decision with the session cookie and the CSRF token.
  defp decide(signed_in, params) do
    {session, token} = csrf(signed_in)

    session
    |> recycle()
    |> put_req_header("x-csrf-token", token)
    |> post("/oauth/authorize", params)
  end

  defp code_from(response) do
    %{"redirect_to" => url} = json_response(response, 200)
    assert String.starts_with?(url, @redirect <> "?")
    query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["state"] == "xyz"
    query["code"]
  end

  defp exchange(conn, client_id, code, extra \\ %{}) do
    post(
      conn,
      "/oauth/token",
      Map.merge(
        %{
          "grant_type" => "authorization_code",
          "code" => code,
          "client_id" => client_id,
          "redirect_uri" => @redirect,
          "code_verifier" => @verifier
        },
        extra
      )
    )
  end

  defp connect_client(conn, email) do
    signed_in = register(conn, email)
    client_id = register_client(build_conn())

    code =
      signed_in |> decide(authorize_params(client_id, %{"decision" => "approve"})) |> code_from()

    tokens = build_conn() |> exchange(client_id, code) |> json_response(200)
    {signed_in, client_id, code, tokens}
  end

  defp mcp(token, method, params \\ %{}) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: method, params: params})
  end

  test "discovery documents name the endpoints", %{conn: conn} do
    resource = conn |> get("/.well-known/oauth-protected-resource") |> json_response(200)
    assert resource["resource"] =~ "/mcp"

    server = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)
    assert server["code_challenge_methods_supported"] == ["S256"]
    assert server["registration_endpoint"] =~ "/oauth/register"
  end

  test "registration rejects a redirect URI that is neither HTTPS nor loopback", %{conn: conn} do
    body = %{client_name: "Evil", redirect_uris: ["http://example.com/cb"]}

    assert %{"error" => "invalid_client_metadata"} =
             conn |> post("/oauth/register", body) |> json_response(400)
  end

  test "authorize sends the browser to the consent page", %{conn: conn} do
    client_id = register_client(conn)
    response = get(build_conn(), "/oauth/authorize", authorize_params(client_id))
    assert "/connect?" <> _ = redirected_to(response)
  end

  test "authorize rejects an unregistered redirect URI and a missing PKCE challenge", %{
    conn: conn
  } do
    client_id = register_client(conn)
    other = authorize_params(client_id, %{"redirect_uri" => "https://evil.example/cb"})
    assert get(build_conn(), "/oauth/authorize", other).status == 400
    plain = authorize_params(client_id, %{"code_challenge_method" => "plain"})
    assert get(build_conn(), "/oauth/authorize", plain).status == 400
  end

  test "the consent decision needs a signed-in account", %{conn: conn} do
    client_id = register_client(conn)
    {session, token} = csrf(build_conn())

    response =
      session
      |> recycle()
      |> put_req_header("x-csrf-token", token)
      |> post("/oauth/authorize", authorize_params(client_id, %{"decision" => "approve"}))

    assert response.status == 401
  end

  test "denying redirects with access_denied and issues no code", %{conn: conn} do
    signed_in = register(conn, "deny@example.com")
    client_id = register_client(build_conn())

    %{"redirect_to" => url} =
      signed_in
      |> decide(authorize_params(client_id, %{"decision" => "deny"}))
      |> json_response(200)

    assert url =~ "error=access_denied"
    assert url =~ "state=xyz"
    refute url =~ "code="
  end

  test "the full flow gives access to the GM's campaigns and revoking ends it", %{conn: conn} do
    {signed_in, _client_id, _code, tokens} = connect_client(conn, "gm@example.com")
    gm = Fixtures.user_by_email("gm@example.com")
    campaign = Fixtures.campaign(gm, "The Sunken Keep")

    session =
      Ash.create!(Atlas.Campaigns.Session, %{campaign_id: campaign.id}, actor: gm)

    Fixtures.save_section!(
      Atlas.Campaigns.Session,
      session.id,
      :prep,
      [Fixtures.paragraph("Secret twist")],
      gm
    )

    assert %{"token_type" => "Bearer", "access_token" => access, "refresh_token" => _} = tokens

    list = mcp(access, "tools/call", %{name: "list_campaigns", arguments: %{}})
    assert list.status == 200
    assert list.resp_body =~ "The Sunken Keep"

    sessions =
      mcp(access, "tools/call", %{
        name: "list_sessions",
        arguments: %{input: %{campaign_id: campaign.id}}
      })

    assert sessions.resp_body =~ "number"
    refute sessions.resp_body =~ "prep_json"

    read =
      mcp(access, "tools/call", %{name: "get_session", arguments: %{input: %{id: session.id}}})

    assert read.resp_body =~ "Secret twist"

    assert %{"data" => [%{"id" => id, "clientName" => "Claude"}]} =
             rpc(signed_in, "list_mcp_connections", %{fields: ["id", "clientName"]})

    assert %{"success" => true} = rpc(signed_in, "revoke_mcp_connection", %{identity: id})
    assert mcp(access, "tools/list").status == 401
  end

  test "MCP requests without a valid token get the discovery challenge", %{conn: conn} do
    response = post(conn, "/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list"})
    assert response.status == 401
    assert [challenge] = get_resp_header(response, "www-authenticate")
    assert challenge =~ "resource_metadata="

    assert mcp("nope", "tools/list").status == 401
  end

  test "a code works once", %{conn: conn} do
    {_signed_in, client_id, code, _tokens} = connect_client(conn, "once@example.com")

    assert %{"error" => "invalid_grant"} =
             build_conn() |> exchange(client_id, code) |> json_response(400)
  end

  test "a wrong PKCE verifier or client fails the exchange", %{conn: conn} do
    signed_in = register(conn, "pkce@example.com")
    client_id = register_client(build_conn())
    other_client = register_client(build_conn())
    params = authorize_params(client_id, %{"decision" => "approve"})

    code = signed_in |> decide(params) |> code_from()

    bad =
      build_conn() |> exchange(client_id, code, %{"code_verifier" => String.duplicate("x", 50)})

    assert bad.status == 400

    code = signed_in |> decide(params) |> code_from()
    assert build_conn() |> exchange(other_client, code) |> Map.fetch!(:status) == 400
  end

  test "a refresh token rotates", %{conn: conn} do
    {_signed_in, client_id, _code, tokens} = connect_client(conn, "refresh@example.com")

    refresh = fn token ->
      post(build_conn(), "/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => token,
        "client_id" => client_id
      })
    end

    fresh = refresh.(tokens["refresh_token"]) |> json_response(200)
    assert fresh["access_token"] != tokens["access_token"]
    assert mcp(fresh["access_token"], "tools/list").status == 200
    assert mcp(tokens["access_token"], "tools/list").status == 401
    assert refresh.(tokens["refresh_token"]).status == 400
  end
end
