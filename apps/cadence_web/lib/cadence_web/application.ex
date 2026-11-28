defmodule CadenceWeb.Application do
  @moduledoc false

  use Application

  alias CadenceWeb.Observability.RequestCost

  @request_cost Application.compile_env(:cadence_web, :request_cost, false)

  @impl true
  def start(_type, _args) do
    CadenceWeb.Observability.setup_web_tracing()

    if @request_cost do
      RequestCost.setup()
    end

    children = [
      {Phoenix.PubSub, name: CadenceWeb.PubSub},
      CadenceWeb.FrontendReleasePublication.Janitor,
      CadenceWeb.Console.LimitTransitions,
      {Task.Supervisor, name: CadenceWeb.Console.TaskSupervisor},
      # The live fleet push reads each mission once, not once per socket (#797).
      {Registry, keys: :unique, name: CadenceWeb.Console.FleetSources},
      {DynamicSupervisor, name: CadenceWeb.Console.FleetSourceSupervisor, strategy: :one_for_one},
      CadenceWeb.Console.ContactChanges,
      CadenceWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CadenceWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CadenceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
