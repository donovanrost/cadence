defmodule Cadence.OTPClusterSpike.Node do
  @moduledoc false
  use Application

  def boot(hosts) do
    specification = [
      description: ~c"Isolated OTP cluster spike",
      vsn: ~c"1",
      applications: [:kernel, :stdlib, :elixir, :logger],
      mod: {__MODULE__, hosts}
    ]

    :ok = :application.load({:application, :cadence_otp_spike, specification})
    Application.ensure_all_started(:cadence_otp_spike)
  end

  @impl true
  def start(_type, hosts) do
    topology = [
      spike: [strategy: Cluster.Strategy.Epmd, config: [hosts: hosts, timeout: 100]]
    ]

    children = [
      {Cluster.Supervisor, [topology, [name: Cadence.OTPClusterSpike.Discovery]]},
      Cadence.OTPClusterSpike.Pools,
      Cadence.OTPClusterSpike.Membership
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Cadence.OTPClusterSpike.Root)
  end
end
