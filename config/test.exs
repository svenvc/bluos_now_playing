import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bluos_now_playing, BluOSNowPlayingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3wZG6A7B68KvLyzywVNSF7ij4055shWyI81fditXE+IQknTkcCPl8+dJ/ML+m7f9",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
