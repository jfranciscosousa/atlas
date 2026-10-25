defmodule AtlasWeb.McpHelpers do
  @moduledoc false
  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint AtlasWeb.Endpoint

  # A grant with a known token stands in for the OAuth flow, which `McpOAuthTest` covers.
  def token_for(user) do
    client =
      Ash.create!(Atlas.Mcp.Client, %{redirect_uris: ["https://a.example/cb"]}, authorize?: false)

    token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    Atlas.Mcp.Grant
    |> Ash.create!(
      %{
        user_id: user.id,
        client_id: client.id,
        code_challenge: "unused",
        redirect_uri: "https://a.example/cb"
      },
      authorize?: false
    )
    |> Ash.Changeset.for_update(
      :issue_tokens,
      %{
        access_token_hash: Base.encode16(:crypto.hash(:sha256, token), case: :lower),
        access_expires_at: DateTime.add(DateTime.utc_now(), 600)
      },
      authorize?: false
    )
    |> Ash.update!()

    token
  end

  # Returns the decoded text of the tool result and whether it is an error.
  def call(token, name, arguments) do
    response =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("accept", "application/json, text/event-stream")
      |> post("/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{name: name, arguments: arguments}
      })
      |> json_response(200)

    %{"content" => [%{"text" => text}], "isError" => error?} = response["result"]
    {error?, text}
  end

  def ok!(token, name, arguments) do
    assert {false, text} = call(token, name, arguments)
    Jason.decode!(text)
  end
end
