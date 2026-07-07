import Config

# Test-only secret; generate your own with `mix fractal.gen.secret`
config :fractal,
  secret_key_base:
    "9t25NH+Giutf/wNBkdrvw6eDO6dv6QggHy8SVLUSUNe4Cj7a2OSM8xRY0j/ctV6SnQfkOtrRjZaJMqPOavSEmw=="

config :blog, Blog.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "blog_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Discovery products (the route table, the CSS bundle) are cached
# outside dev; tests stay on the live path so nothing can go stale
# mid-suite no matter what they mutate or toggle.
config :fractal, cache_discovery: false

config :logger, level: :warning
