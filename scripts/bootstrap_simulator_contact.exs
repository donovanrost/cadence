{:ok, _started} = Application.ensure_all_started(:req)
CadenceSimulator.SimulatorContactBootstrap.run_from_env()
