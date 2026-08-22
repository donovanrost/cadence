ExUnit.start()
Logger.configure(level: Application.get_env(:logger, :level, :warning))

case System.get_env("CADENCE_TEST_PLANE") do
  plane when plane in [nil, ""] ->
    {:ok, _started_apps} = Application.ensure_all_started(:cadence)

    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)

  plane ->
    {:ok, _started_apps} = Application.ensure_all_started(:telemetry)

    if plane in ["data", "projections"] do
      {:ok, _started_apps} = Application.ensure_all_started(:opentelemetry)
    end
end
