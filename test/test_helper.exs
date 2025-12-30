{:ok, _} = Application.ensure_all_started(:cadence)
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)
