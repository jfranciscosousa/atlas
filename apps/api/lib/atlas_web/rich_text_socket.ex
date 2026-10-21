defmodule AtlasWeb.RichTextSocket do
  @moduledoc """
  The WebSocket that carries live editing.

  It accepts the same signed-in browser session as the JSON API: the session cookie, plus the
  CSRF token that `GET /api/session` returns, sent as `_csrf_token`. A request from another site
  has neither the cookie (SameSite), nor the token, nor an allowed origin (the endpoint checks it).
  """
  use Phoenix.Socket

  alias AshAuthentication.Plug.Helpers

  channel "doc:*", AtlasWeb.RichTextChannel

  # Phoenix has already matched the `_csrf_token` parameter against the session's CSRF state:
  # without a match `connect_info.session` is nil.
  @impl true
  def connect(_params, socket, %{session: session}) when is_map(session) do
    case user(session) do
      {:ok, user} -> {:ok, socket |> assign(:session, session) |> assign(:user, user)}
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @doc "The signed-in user of a session. Fails for a signed-out or revoked session."
  def user(session),
    do: Helpers.authenticate_resource_from_session(Atlas.Accounts.User, session, :atlas, [])

  @impl true
  def id(%{assigns: %{user: user}}), do: "rich_text_socket:#{user.id}"
end
