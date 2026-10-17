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

  scope "/", AtlasWeb do
    pipe_through :api

    get "/api/session", SessionController, :show
    delete "/api/session", SessionController, :delete
    post "/rpc/run", AshTypescriptRpcController, :run
    post "/rpc/validate", AshTypescriptRpcController, :validate

    for name <- [:password, :confirm_new_user],
        strategy = AshAuthentication.Info.strategy!(Atlas.Accounts.User, name),
        {path, phase} <- AshAuthentication.Strategy.routes(strategy),
        AshAuthentication.Strategy.method_for_phase(strategy, phase) == :post do
      post "/auth" <> path, AuthController, {:user, name, phase}, private: %{strategy: strategy}
    end
  end

  if Application.compile_env(:atlas, :dev_routes) do
    scope "/dev" do
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
