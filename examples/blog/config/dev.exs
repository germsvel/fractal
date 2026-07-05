import Config

# Dev-only secret; generate your own with `mix fractal.gen.secret`
config :fractal,
  secret_key_base:
    "udFfelu9J6Z55jb4PKiX4psEwr17A2I5YkFJoaAPtTIlUHeiAvgTmptrlnWqkRTYqz2zyA1ahiERumQOHMuiCg=="

config :blog, Blog.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "blog_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
