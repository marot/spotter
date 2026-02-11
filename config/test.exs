import Config

config :spotter, Oban, testing: :manual
config :logger, level: :warning

config :spotter, Spotter.Repo,
  database: Path.join(__DIR__, "../path/to/your#{System.get_env("MIX_TEST_PARTITION")}.db"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :spotter, SpotterWeb.Endpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: String.duplicate("test_secret_key_base_", 4)

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true
