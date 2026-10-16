defmodule LemonadeStandWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :lemonade_stand

  @session_options [
    store: :cookie,
    key: "_lemonade_stand_key",
    signing_salt: "Emd3hwBg",
    same_site: "Lax",
    secure: Application.compile_env(:lemonade_stand, :secure_cookies, false)
  ]

  if Mix.env() == :dev do
    plug Tidewave
  end

  if code_reloading? do
    plug AshAi.Mcp.Dev, otp_app: :lemonade_stand, path: "/ash_ai/mcp"
    plug Phoenix.CodeReloader
    plug AshPhoenix.Plug.CheckCodegenStatus
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :lemonade_stand
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug Plug.Session, @session_options
  plug LemonadeStandWeb.Router
end
