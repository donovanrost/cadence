defmodule Cadence.Runtime.Interfaces.PerInterfaceSupervisor do
  @moduledoc """
  Supervisor for per-interface runtime processes.
  """

  use Supervisor

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.Factory
  alias Cadence.Runtime.Telemetry.{DeframeSupervisor, DownlinkPipeline, UplinkPipeline}

  def start_link(%Interface{} = interface) do
    Supervisor.start_link(__MODULE__, interface)
  end

  @impl true
  def init(%Interface{} = interface) do
    interface_module = Factory.module_for_connection_type(interface.connection_type)

    children = [
      {DeframeSupervisor, mission_id: interface.mission_id, interface_id: interface.id},
      {DownlinkPipeline, interface: interface},
      {UplinkPipeline, interface: interface},
      {interface_module, interface}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def child_spec(%Interface{} = interface) do
    %{
      id: {:per_interface_supervisor, interface.id},
      start: {__MODULE__, :start_link, [interface]},
      type: :supervisor
    }
  end
end
