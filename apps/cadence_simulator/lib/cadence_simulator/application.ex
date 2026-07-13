defmodule CadenceSimulator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {DynamicSupervisor, strategy: :one_for_one, name: CadenceSimulator.RuntimeSupervisor},
        {CadenceSimulator.Provider.Store, store_options()},
        {CadenceSimulator.Provider.Orchestrator, []}
      ] ++ http_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: CadenceSimulator.Supervisor)
  end

  defp store_options do
    Application.get_env(:cadence_simulator, :provider_store,
      path: Path.expand("var/cadence_simulator_provider.dets")
    )
  end

  defp http_children do
    config = Application.get_env(:cadence_simulator, :provider_http, [])

    if Keyword.get(config, :enabled, false) do
      [
        {Bandit,
         plug: CadenceSimulator.Provider.Router,
         scheme: :http,
         ip: Keyword.get(config, :ip, {127, 0, 0, 1}),
         port: Keyword.get(config, :port, 4101)}
      ]
    else
      []
    end
  end
end
