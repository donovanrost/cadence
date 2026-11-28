ExUnit.configure(exclude: [:browser, :browser_smoke, :scale])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)
