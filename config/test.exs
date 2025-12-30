import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :cadence, Cadence.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cadence_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cadence, CadenceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xtiGgcDSi5w21xxoUibRp89fNerx6Bftg2s6w91dddFrcR9xRs95+GyuxwS8vKyW",
  server: false

# In test we don't send emails
config :cadence, Cadence.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
# Note: Some Postgrex disconnection errors may still appear during sandbox cleanup
# when GenServers exit - these are expected and not indicative of actual problems
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable the outbox processor in tests - tests should manage their own processing
config :cadence, Cadence.Outbox.Processor, enabled: false

# Disable queue persistence in tests to avoid sandbox ownership issues.
config :cadence, Cadence.Application.Commanding.QueuePersistence, enabled: false

# Configure Oban for testing - inline execution
config :cadence, Oban, testing: :inline

# Run TargetQueue persistence inline in tests to avoid leaking DB tasks.
config :cadence, Cadence.Runtime.Commands.TargetQueue, persist_async?: false

# Disable auto-start in ExecutionProcess; tests can start it explicitly.
config :cadence, Cadence.Procedures.Engine.ExecutionProcess, autostart_pending?: false

# =============================================================================
# Ports & Adapters Test Configuration (Hexagonal Architecture)
#
# By default, tests still use Ecto repositories (via DataCase).
# For pure unit tests (PureCase), start the fake adapters manually in setup.
#
# To use fake adapters globally, uncomment the lines below. However, this is
# generally not recommended as most tests benefit from integration testing
# with the real database.
# =============================================================================

# Fake email sender for tests (use FakeEmailSender.start_link() in setup)
# config :cadence, :email_sender, Cadence.Test.Adapters.FakeEmailSender

# Fake event publisher for tests (use FakeEventPublisher.start_link() in setup)
# config :cadence, :event_publisher, Cadence.Test.Adapters.FakeEventPublisher

# Fake event recorder for tests (use InMemoryEventRecorder.start_link() in setup)
# config :cadence, :event_recorder, Cadence.Test.Adapters.InMemoryEventRecorder

# Note: For pure unit tests using PureCase, you'll typically start the fake
# adapters in the test setup and configure them via Application.put_env/3.
# This gives you more control over the test lifecycle.
#
# Example:
#   setup do
#     {:ok, _} = FakeEmailSender.start_link()
#     Application.put_env(:cadence, :email_sender, Cadence.Test.Adapters.FakeEmailSender)
#     on_exit(fn -> Application.delete_env(:cadence, :email_sender) end)
#     :ok
#   end
