defmodule CadenceWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    CadenceWeb.Observability.setup_web_tracing()

    children = [
      {Phoenix.PubSub, name: CadenceWeb.PubSub},
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
