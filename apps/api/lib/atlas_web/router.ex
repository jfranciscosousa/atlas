defmodule AtlasWeb.Router do
  use AtlasWeb, :router

  import AshAuthentication.Plug.Helpers
  import AshAuthentication.Phoenix.Plug

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug :set_actor, :user
  end

  pipeline :mcp do
    plug AtlasWeb.Plugs.McpAuth
  end

  # The MCP server and its OAuth endpoints. Clients authenticate with a bearer token or none, so
  # there is no session and no CSRF check here.
  scope "/", AtlasWeb do
    get "/.well-known/oauth-protected-resource", OAuthMetadataController, :protected_resource
    get "/.well-known/oauth-protected-resource/mcp", OAuthMetadataController, :protected_resource
    get "/.well-known/oauth-authorization-server", OAuthMetadataController, :authorization_server

    post "/oauth/register", OAuthController, :register
    get "/oauth/authorize", OAuthController, :authorize
    post "/oauth/token", OAuthController, :token
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      otp_app: :atlas,
      tools: [
        :list_campaigns,
        :get_campaign,
        :list_sessions,
        :get_session,
        :list_characters,
        :get_character,
        :list_notes,
        :get_note,
        :list_player_logs,
        :get_player_log,
        :create_campaign,
        :create_session,
        :update_session,
        :rename_character,
        :create_note,
        :rename_note,
        :archive_note,
        :restore_note,
        :reveal_note,
        :hide_note,
        :upload_image,
        :write_text
      ]
  end

  scope "/", AtlasWeb do
    pipe_through :api

    get "/api/session", SessionController, :show
    delete "/api/session", SessionController, :delete
    post "/rpc/run", AshTypescriptRpcController, :run
    post "/rpc/validate", AshTypescriptRpcController, :validate

    post "/api/images", ImageUploadController, :create

    # The consent page of the web app posts the decision here.
    post "/oauth/authorize", OAuthController, :decide

    for name <- [:password, :confirm_new_user],
        strategy = AshAuthentication.Info.strategy!(Atlas.Accounts.User, name),
        {path, phase} <- AshAuthentication.Strategy.routes(strategy),
        AshAuthentication.Strategy.method_for_phase(strategy, phase) == :post do
      post "/auth" <> path, AuthController, {:user, name, phase}, private: %{strategy: strategy}
    end
  end

  # Signed-URL delivery. The URL is the credential, so there is no session or JSON negotiation.
  scope "/", AtlasWeb do
    get "/api/images/:token", ImageController, :show
  end

  if Application.compile_env(:atlas, :dev_routes) do
    scope "/dev" do
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
