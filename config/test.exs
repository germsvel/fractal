import Config

# Test-only secret; generate your own with `mix fractal.gen.secret`
config :fractal,
  secret_key_base:
    "9t25NH+Giutf/wNBkdrvw6eDO6dv6QggHy8SVLUSUNe4Cj7a2OSM8xRY0j/ctV6SnQfkOtrRjZaJMqPOavSEmw=="

config :fractal, Fractal.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "fractal_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :logger, level: :warning
