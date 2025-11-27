defmodule Cadence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CadenceWeb.Telemetry,
      Cadence.Repo,
      {DNSCluster, query: Application.get_env(:cadence, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Cadence.PubSub},

      # Mission Registry - registers all mission processes
      {Registry, keys: :unique, name: Cadence.MissionRegistry},

      # Protocol Chain Registry - registers protocol chains by interface_id
      {Registry, keys: :unique, name: Cadence.ProtocolChainRegistry},

      # Derived Items Cache - caches derived item definitions per mission
      Cadence.Telemetry.DerivedItems.Cache,

      # Processor State - ETS storage for stateful derived item functions
      Cadence.Telemetry.DerivedItems.ProcessorState,

      # Limits Cache - caches limits configurations per mission/target
      Cadence.Telemetry.Limits.Cache,

      # Mission Supervisor - manages all mission supervision trees
      Cadence.Missions.MissionSupervisor,

      # Start to serve requests, typically the last entry
      CadenceWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cadence.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # Bootstrap system admin after supervisor starts
      ensure_system_admin()
      {:ok, pid}
    end
  end

  defp ensure_system_admin do
    email = System.get_env("SYSTEM_ADMIN_EMAIL")
    password = System.get_env("SYSTEM_ADMIN_PASSWORD")

    if email && password do
      Cadence.Accounts.ensure_system_admin(email, password)
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CadenceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
