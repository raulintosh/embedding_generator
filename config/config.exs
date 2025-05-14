# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :embedding_generator,
  ecto_repos: [EmbeddingGenerator.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :embedding_generator, EmbeddingGeneratorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EmbeddingGeneratorWeb.ErrorHTML, json: EmbeddingGeneratorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EmbeddingGenerator.PubSub,
  live_view: [signing_salt: "u6WtYdoQ"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :embedding_generator, EmbeddingGenerator.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  embedding_generator: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  embedding_generator: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration
config :embedding_generator, Oban,
  repo: EmbeddingGenerator.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [embeddings: 10]

# ObanWeb configuration
config :oban_web,
  repo: EmbeddingGenerator.Repo,
  prefix: "oban_jobs",
  oban_name: Oban

# Configure batch processing
config :embedding_generator, EmbeddingGenerator.BatchProcessor,
  # Default batch size, can be overridden at runtime
  batch_size: 5

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
