defmodule CadenceSimulator do
  @moduledoc """
  Simulator-specific generation and networking helpers.

  This app is the extraction target for the legacy simulator subsystem so it
  can evolve as an external peer to Cadence rather than a privileged mix task.
  """

  alias CadenceSimulator.Coordinator
  alias CadenceSimulator.COP1.LoopbackPeer

  @spec start_simulator(keyword()) :: DynamicSupervisor.on_start_child()
  def start_simulator(opts) when is_list(opts) do
    child_spec = Supervisor.child_spec({Coordinator, opts}, restart: :temporary)
    DynamicSupervisor.start_child(CadenceSimulator.RuntimeSupervisor, child_spec)
  end

  @spec start_cop1_loopback_peer(keyword()) :: DynamicSupervisor.on_start_child()
  def start_cop1_loopback_peer(opts) when is_list(opts) do
    child_spec = Supervisor.child_spec({LoopbackPeer, opts}, restart: :temporary)
    DynamicSupervisor.start_child(CadenceSimulator.RuntimeSupervisor, child_spec)
  end

  @spec stop_simulator(pid()) :: :ok | {:error, :not_found}
  def stop_simulator(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(CadenceSimulator.RuntimeSupervisor, pid)
  end

  @spec set_simulator_rate(pid(), number()) :: :ok | {:error, :invalid_rate_hz}
  def set_simulator_rate(pid, rate_hz) when is_pid(pid) and is_number(rate_hz) do
    Coordinator.set_rate(pid, rate_hz)
  end

  @spec simulator_stats(pid()) :: map()
  def simulator_stats(pid) when is_pid(pid) do
    Coordinator.stats(pid)
  end

  @spec await_simulator(pid()) :: {:ok, term()}
  def await_simulator(pid) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:ok, reason}
    end
  end
end
