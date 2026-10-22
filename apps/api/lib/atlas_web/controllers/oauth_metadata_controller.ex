defmodule AtlasWeb.OAuthMetadataController do
  @moduledoc "Discovery documents for MCP clients (RFC 9728 and RFC 8414)."
  use AtlasWeb, :controller

  @doc "The public base URL of the app. Behind the proxy the API cannot derive it."
  def base_url, do: Application.fetch_env!(:atlas, :frontend_url)

  def protected_resource(conn, _params) do
    json(conn, %{
      resource: base_url() <> "/mcp",
      authorization_servers: [base_url()],
      bearer_methods_supported: ["header"]
    })
  end

  def authorization_server(conn, _params) do
    base = base_url()

    json(conn, %{
      issuer: base,
      authorization_endpoint: base <> "/oauth/authorize",
      token_endpoint: base <> "/oauth/token",
      registration_endpoint: base <> "/oauth/register",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"]
    })
  end
end
