import Config

config :fractal, Fractal.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "fractal_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
