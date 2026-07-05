import Config

config :fractal, secret_key_base: System.get_env("SECRET_KEY_BASE")

config :blog, Blog.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))
