ExUnit.configure(exclude: [:browser, :browser_smoke])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)
