defmodule AtlasWeb.Plugs.McpAuth do
  @moduledoc """
  Authenticates an MCP request with an OAuth access token and sets the account as the Ash actor.
  An unauthenticated request gets the 401 that tells the client where to find the discovery
  document (RFC 9728).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Atlas.Mcp.OAuth.authenticate(token) do
      Ash.PlugHelpers.set_actor(conn, user)
    else
      _ ->
        metadata =
          AtlasWeb.OAuthMetadataController.base_url() <> "/.well-known/oauth-protected-resource"

        conn
        |> put_resp_header("www-authenticate", ~s(Bearer resource_metadata="#{metadata}"))
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"unauthorized"}))
        |> halt()
    end
  end
end
