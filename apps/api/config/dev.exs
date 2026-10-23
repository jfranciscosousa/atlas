import Config

config :ash, policies: [show_policy_breakdowns?: true]
# Set FRONTEND_URL to the public URL (for example the Tailscale one) to connect an MCP client.
config :atlas, frontend_url: System.get_env("FRONTEND_URL", "http://localhost:3000")

{db_suffix, _} = Code.eval_file("worktree.exs", __DIR__)

config :atlas, Atlas.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: "atlas_dev#{db_suffix}",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :atlas, AtlasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  code_reloader: true,
  debug_errors: true,
  # The live-editing socket accepts only these origins. Add a host (for example a Tailscale name)
  # with ALLOWED_ORIGINS="//host.example,//other.example".
  check_origin:
    ["//localhost", "//127.0.0.1"] ++
      String.split(System.get_env("ALLOWED_ORIGINS", ""), ",", trim: true),
  secret_key_base: "MlCuZ6YlCxC2KY/xPksM+ZxGjWIxluwrsBCUdlO8GJfXTjECFmN20M151QoOTcLm"

config :atlas, dev_routes: true, token_signing_secret: "eF8H1KDP4nbpf/302Vcy/W6hSJBh9LmE"
config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :swoosh, :api_client, false
