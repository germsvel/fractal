import Config

# Test-only secret; generate your own with `mix fractal.gen.secret`
config :fractal,
  secret_key_base:
    "9t25NH+Giutf/wNBkdrvw6eDO6dv6QggHy8SVLUSUNe4Cj7a2OSM8xRY0j/ctV6SnQfkOtrRjZaJMqPOavSEmw=="

# watch connections notice a closed socket at the next keepalive; keep
# it short so server shutdown doesn't wait on lingering SSE processes
config :fractal, watch_keepalive_ms: 100

config :logger, level: :warning
