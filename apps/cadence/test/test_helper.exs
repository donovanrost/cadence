ExUnit.start()

{:ok, _started_apps} = Application.ensure_all_started(:cadence)

Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)
