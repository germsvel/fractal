import Config

config :blog, ecto_repos: [Blog.Repo]

import_config "#{config_env()}.exs"
