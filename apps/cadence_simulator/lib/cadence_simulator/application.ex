defmodule CadenceSimulator.Application do
  @moduledoc false

  use Application

  alias CadenceSimulator.Provider.{Configuration, Orchestrator, Router, Store}

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(Configuration.snapshot()),
      strategy: :one_for_one,
      name: CadenceSimulator.Supervisor
    )
  end

  @doc false
  @spec children(Configuration.t()) :: [Supervisor.child_spec() | {module(), term()}]
  def children(%Configuration{} = configuration) do
    [
      {DynamicSupervisor, strategy: :one_for_one, name: CadenceSimulator.RuntimeSupervisor},
      {Store, configuration.store},
      {Orchestrator, Configuration.orchestrator_options(configuration)}
    ] ++ http_children(configuration)
  end

  defp http_children(%Configuration{http: config} = configuration) do
    enabled? = Keyword.get(config, :enabled, false)

    if enabled? do
      [
        {Bandit,
         plug: {Router, Configuration.router_options(configuration)},
         scheme: :http,
         ip: Keyword.get(config, :ip, {127, 0, 0, 1}),
         port: Keyword.get(config, :port, 4101)}
      ]
    else
      []
    end
  end
end
