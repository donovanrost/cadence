require Logger

{:ok, _} = Application.ensure_all_started(:logger)
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)

case Cadence.Repo.start_link() do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
  {:error, _} -> :ok
end

case Phoenix.PubSub.Supervisor.start_link(name: Cadence.PubSub) do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
  {:error, _} -> :ok
end

truncate_test_database = fn ->
  {:ok, %{rows: rows}} =
    Ecto.Adapters.SQL.query(
      Cadence.Repo,
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'",
      []
    )

  table_names = Enum.map(rows, &hd/1)

  if table_names != [] do
    quoted_tables = Enum.map_join(table_names, ", ", &~s|"#{&1}"|)

    Ecto.Adapters.SQL.query!(
      Cadence.Repo,
      "TRUNCATE TABLE #{quoted_tables} RESTART IDENTITY CASCADE",
      []
    )
  end
end

truncate_test_database.()

capture_logs? =
  case System.get_env("CADENCE_TEST_VERBOSE") do
    "1" -> false
    "true" -> false
    "TRUE" -> false
    _ -> true
  end

integration_run? =
  case System.get_env("CADENCE_INTEGRATION") do
    "1" -> true
    "true" -> true
    "TRUE" -> true
    _ -> false
  end

if integration_run? do
  Application.put_env(:cadence, :integration_mode, true)
  ExUnit.start(capture_log: capture_logs?)
  Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)
else
  ExUnit.start(exclude: [integration: true], capture_log: capture_logs?)
  Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)
end

log_level =
  case System.get_env("CADENCE_TEST_LOG_LEVEL") do
    "debug" ->
      :debug

    "info" ->
      :info

    "warning" ->
      :warning

    "warn" ->
      :warning

    "error" ->
      :error

    _ ->
      case System.get_env("CADENCE_TEST_VERBOSE") do
        "1" -> :info
        "true" -> :info
        "TRUE" -> :info
        _ -> :error
      end
  end

Logger.configure(level: log_level)

case System.get_env("CADENCE_TEST_VERBOSE") do
  "1" ->
    :ok

  "true" ->
    :ok

  "TRUE" ->
    :ok

  _ ->
    quiet_modules = [
      Cadence.Procedures.Dag.Executor,
      Cadence.Procedures.Dag.StepExecutor,
      Cadence.Runtime.Commands.TargetDispatcher,
      Cadence.Runtime.Interfaces.TcpServerInterface,
      Cadence.Runtime.Missions.CacheWarmer,
      Cadence.Runtime.Missions.MissionSupervisor,
      Cadence.Runtime.Telemetry.PipelineV2.Stages.IdentifyStage,
      Cadence.Runtime.Telemetry.PipelineV2.Stages.StageBehaviour,
      Cadence.Telemetry.Decommutation,
      Cadence.Telemetry.Protocols.CCSDSProtocol,
      Cadence.Telemetry.Protocols.CRCProtocol,
      Postgrex.Protocol
    ]

    Enum.each(quiet_modules, &Logger.put_module_level(&1, :critical))

    if function_exported?(:logger, :set_module_level, 2) do
      Enum.each(quiet_modules, &:logger.set_module_level(&1, :critical))
    end

    if function_exported?(:logger, :add_primary_filter, 2) do
      :logger.add_primary_filter(:cadence_test_noise, {Cadence.TestLogFilter, %{}})
    end
end
