import Config

config :fractal, ecto_repos: [Fractal.Repo]

import_config "#{config_env()}.exs"
