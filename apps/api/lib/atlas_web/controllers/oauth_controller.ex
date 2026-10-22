defmodule AtlasWeb.OAuthController do
  @moduledoc """
  The OAuth endpoints of the MCP server. The consent screen is a page of the web app: `authorize`
  sends the browser there, and the page posts the decision back to `decide`.
  """
  use AtlasWeb, :controller

  alias Atlas.Mcp.OAuth

  def register(conn, params) do
    case OAuth.register(params) do
      {:ok, client} ->
        conn
        |> put_status(:created)
        |> json(%{
          client_id: client.id,
          client_name: client.name,
          redirect_uris: client.redirect_uris,
          grant_types: ["authorization_code", "refresh_token"],
          response_types: ["code"],
          token_endpoint_auth_method: "none"
        })

      {:error, description} ->
        error(conn, "invalid_client_metadata", description)
    end
  end

  # The MCP client sends the browser here. The web app asks for consent.
  def authorize(conn, params) do
    case OAuth.authorization_request(params) do
      {:ok, _client, _request} ->
        redirect(conn, external: "/connect?" <> conn.query_string)

      {:error, description} ->
        error(conn, "invalid_request", description)
    end
  end

  # The consent page posts here with the session cookie and the CSRF token.
  def decide(conn, params) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, client, request} <- OAuth.authorization_request(params) do
      query =
        if params["decision"] == "approve" do
          %{code: OAuth.approve(user, client, request)}
        else
          %{error: "access_denied"}
        end

      query = if params["state"], do: Map.put(query, :state, params["state"]), else: query

      json(conn, %{
        redirect_to:
          URI.append_query(URI.parse(request.redirect_uri), URI.encode_query(query))
          |> to_string()
      })
    else
      nil -> conn |> put_status(:unauthorized) |> json(%{error: "Sign in to continue."})
      {:error, description} -> error(conn, "invalid_request", description)
    end
  end

  def token(conn, params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case OAuth.token(params) do
      {:ok, tokens} -> json(conn, tokens)
      {:error, code} -> error(conn, code, nil)
    end
  end

  defp error(conn, code, description) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: code, error_description: description})
  end
end
