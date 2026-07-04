import Config

config :fractal, ecto_repos: [Fractal.Repo]

# Extra response headers, merged over Fractal's secure defaults
# (x-content-type-options, x-frame-options, referrer-policy):
#
#     config :fractal, :response_headers, %{"permissions-policy" => "camera=()"}

import_config "#{config_env()}.exs"
