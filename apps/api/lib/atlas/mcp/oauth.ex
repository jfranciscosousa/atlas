defmodule Atlas.Mcp.OAuth do
  @moduledoc """
  The OAuth 2.1 rules of the MCP endpoint: dynamic client registration (RFC 7591), the
  authorization code flow with PKCE (S256 only), and refresh token rotation.

  Every client is public. A code lives 60 seconds and works once. An access token lives one hour.
  A refresh token lives until the account revokes the connection, and each use replaces it.
  """
  require Ash.Query

  alias Atlas.Mcp.Client
  alias Atlas.Mcp.Grant

  @code_ttl 60
  @access_ttl 3600
  @loopback ["localhost", "127.0.0.1", "[::1]", "::1"]

  @doc "Registers a client. Returns `{:ok, client}` or `{:error, description}`."
  def register(%{"redirect_uris" => uris} = params) when is_list(uris) do
    if uris != [] and Enum.all?(uris, &redirect_uri?/1) do
      attrs = %{name: params["client_name"], redirect_uris: uris}
      attrs = if is_binary(attrs.name), do: attrs, else: Map.delete(attrs, :name)

      case Ash.create(Client, attrs, action: :register, authorize?: false) do
        {:ok, client} -> {:ok, client}
        {:error, _} -> {:error, "The client metadata is not valid."}
      end
    else
      {:error, "Each redirect URI must use HTTPS, or HTTP on localhost."}
    end
  end

  def register(_), do: {:error, "redirect_uris is required."}

  defp redirect_uri?(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "https", host: host, fragment: nil} -> is_binary(host) and host != ""
      %URI{scheme: "http", host: host, fragment: nil} -> host in @loopback
      _ -> false
    end
  end

  defp redirect_uri?(_), do: false

  @doc """
  Checks an authorization request. It returns the client and the request fields, or an error
  description. The redirect URI must match one that the client registered.
  """
  def authorization_request(params) do
    challenge = params["code_challenge"]

    with :ok <- check(params["response_type"] == "code", "response_type must be code."),
         :ok <- check(params["code_challenge_method"] == "S256", "Use PKCE with S256."),
         :ok <-
           check(
             is_binary(challenge) and byte_size(challenge) in 43..128,
             "code_challenge is missing or malformed."
           ),
         {:ok, client} <- fetch_client(params["client_id"]),
         :ok <-
           check(
             params["redirect_uri"] in client.redirect_uris,
             "redirect_uri is not registered."
           ) do
      {:ok, client, %{redirect_uri: params["redirect_uri"], code_challenge: challenge}}
    end
  end

  defp check(true, _), do: :ok
  defp check(false, description), do: {:error, description}

  defp fetch_client(id) do
    case Ash.get(Client, id, authorize?: false) do
      {:ok, client} -> {:ok, client}
      {:error, _} -> {:error, "client_id is unknown."}
    end
  end

  @doc "Records the user's consent and returns the one-time code."
  def approve(user, client, %{redirect_uri: redirect_uri, code_challenge: challenge}) do
    code = random()

    Ash.create!(
      Grant,
      %{
        user_id: user.id,
        client_id: client.id,
        code_hash: hash(code),
        code_challenge: challenge,
        redirect_uri: redirect_uri,
        code_expires_at: DateTime.add(DateTime.utc_now(), @code_ttl)
      },
      authorize?: false
    )

    code
  end

  @doc "Token endpoint. Returns `{:ok, response_map}` or `{:error, oauth_error_code}`."
  def token(%{"grant_type" => "authorization_code"} = params) do
    with %Grant{} = grant <- grant_by(:code_hash, params["code"]),
         true <- grant.client_id == params["client_id"],
         true <- grant.redirect_uri == params["redirect_uri"],
         true <- DateTime.compare(grant.code_expires_at, DateTime.utc_now()) == :gt,
         true <- pkce?(params["code_verifier"], grant.code_challenge) do
      issue(grant, :code_hash, %{code_hash: nil})
    else
      _ -> {:error, "invalid_grant"}
    end
  end

  def token(%{"grant_type" => "refresh_token"} = params) do
    with %Grant{} = grant <- grant_by(:refresh_token_hash, params["refresh_token"]),
         true <- grant.client_id == params["client_id"] do
      issue(grant, :refresh_token_hash, %{})
    else
      _ -> {:error, "invalid_grant"}
    end
  end

  def token(_), do: {:error, "unsupported_grant_type"}

  defp grant_by(field, secret) when is_binary(secret) do
    Grant |> Ash.Query.do_filter(%{field => hash(secret)}) |> Ash.read_one!(authorize?: false)
  end

  defp grant_by(_, _), do: nil

  defp pkce?(verifier, challenge) when is_binary(verifier) do
    computed = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)
    Plug.Crypto.secure_compare(computed, challenge)
  end

  defp pkce?(_, _), do: false

  # The update matches only while the old secret is still stored. Two requests with one code
  # or one refresh token cannot both win.
  defp issue(grant, used_field, extra) do
    access = random()
    refresh = random()
    used_hash = Map.fetch!(grant, used_field)

    params =
      Map.merge(extra, %{
        access_token_hash: hash(access),
        access_expires_at: DateTime.add(DateTime.utc_now(), @access_ttl),
        refresh_token_hash: hash(refresh)
      })

    result =
      grant
      |> Ash.Changeset.for_update(:issue_tokens, params, authorize?: false)
      |> Ash.Changeset.filter(%{used_field => used_hash})
      |> Ash.update()

    case result do
      {:ok, _} ->
        {:ok,
         %{
           access_token: access,
           token_type: "Bearer",
           expires_in: @access_ttl,
           refresh_token: refresh
         }}

      {:error, _} ->
        {:error, "invalid_grant"}
    end
  end

  @doc "Returns `{:ok, user}` for a live access token."
  def authenticate(token) do
    now = DateTime.utc_now()

    grant =
      Grant
      |> Ash.Query.filter(access_token_hash == ^hash(token) and access_expires_at > ^now)
      |> Ash.Query.load(:user)
      |> Ash.read_one!(authorize?: false)

    case grant do
      nil ->
        :error

      grant ->
        Ash.update!(grant, %{}, action: :touch, authorize?: false)
        {:ok, grant.user}
    end
  end

  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp hash(secret), do: Base.encode16(:crypto.hash(:sha256, secret), case: :lower)
end
