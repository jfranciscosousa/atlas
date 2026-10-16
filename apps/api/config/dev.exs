import Config

config :ash, policies: [show_policy_breakdowns?: true]
config :lemonade_stand, frontend_url: "http://localhost:3000"

config :lemonade_stand, LemonadeStand.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "lemonade_stand_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :lemonade_stand, LemonadeStandWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "MlCuZ6YlCxC2KY/xPksM+ZxGjWIxluwrsBCUdlO8GJfXTjECFmN20M151QoOTcLm"

config :lemonade_stand, dev_routes: true, token_signing_secret: "eF8H1KDP4nbpf/302Vcy/W6hSJBh9LmE"
config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :swoosh, :api_client, false
