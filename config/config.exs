# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cadence, :scopes,
  user: [
    default: true,
    module: Cadence.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Cadence.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :cadence,
  ecto_repos: [Cadence.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :cadence, CadenceWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CadenceWeb.ErrorHTML, json: CadenceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cadence.PubSub,
  live_view: [signing_salt: "Ryg6ElQT"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :cadence, Cadence.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  cadence: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [
        Path.expand("../assets/node_modules", __DIR__),
        Path.expand("../deps", __DIR__),
        Mix.Project.build_path()
      ]
    }
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  cadence: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :mission_id, :target_id, :command, :partition]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# config :cadence, :pipeline_version, :v2

# Configure Oban for background job processing
config :cadence, Oban,
  repo: Cadence.Repo,
  queues: [
    default: 10,
    schedules: 5,
    procedures: 10
  ],
  plugins: [
    Oban.Plugins.Pruner
  ]

# =============================================================================
# Ports & Adapters Configuration (Hexagonal Architecture)
#
# These settings configure which implementations are used for external
# dependencies. Override in environment-specific configs for testing.
# =============================================================================

# Repository adapters (persistence)
# Defaults to Ecto implementations - override in test.exs with in-memory adapters
config :cadence, :alarm_repository, Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository

config :cadence,
       :queue_repository,
       Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository

config :cadence,
       :commands_repository,
       Cadence.Adapters.Persistence.Ecto.Commanding.EctoCommandsRepository

config :cadence,
       :procedure_repository,
       Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository

config :cadence,
       :approval_operations,
       Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository

config :cadence,
       :execution_operations,
       Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository

config :cadence,
       :missions_repository,
       Cadence.Adapters.Persistence.Ecto.Missions.EctoMissionsRepository

config :cadence,
       :settings_repository,
       Cadence.Adapters.Persistence.Ecto.Settings.EctoSettingsRepository

config :cadence,
       :notification_repository,
       Cadence.Adapters.Persistence.Ecto.Notifications.EctoNotificationRepository

config :cadence,
       :target_repository,
       Cadence.Adapters.Persistence.Ecto.Targeting.EctoTargetRepository

config :cadence, :pipeline_version, :lanes

# Messaging adapters
config :cadence, :email_sender, Cadence.Adapters.Messaging.SwooshEmailSender
config :cadence, :event_publisher, Cadence.Adapters.Messaging.PhoenixEventPublisher

# Recordings adapter
config :cadence, :event_recorder, Cadence.Adapters.Recordings.RecordingsEventRecorder

# Base URL for generating links in emails/notifications
# Override in runtime.exs for production
config :cadence, :base_url, "http://localhost:4000"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
