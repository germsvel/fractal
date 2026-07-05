import Config

# Test-only secret; generate your own with `mix fractal.gen.secret`
config :fractal,
  secret_key_base:
    "9t25NH+Giutf/wNBkdrvw6eDO6dv6QggHy8SVLUSUNe4Cj7a2OSM8xRY0j/ctV6SnQfkOtrRjZaJMqPOavSEmw=="

config :logger, level: :warning
