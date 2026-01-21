defmodule Cadence.Runtime.Interfaces.PerInterfaceSupervisor do
  @moduledoc """
  Supervisor for per-interface runtime processes.
  """

  use Supervisor

  alias Cadence.CCSDS.PDUDispatcher
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.Factory
  alias Cadence.Runtime.Telemetry.{DeframeSupervisor, DownlinkPipeline, UplinkPipeline}
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.{FOP, StreamSupervisor}
  alias Cadence.Runtime.Uplink.TCFraming

  def start_link(%Interface{} = interface) do
    Supervisor.start_link(__MODULE__, interface)
  end

  @impl true
  def init(%Interface{} = interface) do
    interface_module = Factory.module_for_connection_type(interface.connection_type)

    children =
      [
        {DeframeSupervisor, mission_id: interface.mission_id, interface_id: interface.id},
        {PDUDispatcher,
         mission_id: interface.mission_id, interface_id: interface.id, interface: interface},
        {DownlinkPipeline, interface: interface},
        {UplinkPipeline, interface: interface},
        {TCFraming, interface: interface},
        {interface_module, interface}
      ]
      |> maybe_add_cop1_fop(interface)

    Supervisor.init(children, strategy: :one_for_one)
  end

  def child_spec(%Interface{} = interface) do
    %{
      id: {:per_interface_supervisor, interface.id},
      start: {__MODULE__, :start_link, [interface]},
      type: :supervisor
    }
  end

  defp maybe_add_cop1_fop(children, %Interface{} = interface) do
    if COP1Application.enabled?(interface) do
      [
        {StreamSupervisor, mission_id: interface.mission_id, interface_id: interface.id},
        {FOP, interface: interface, event_fun: &COP1Application.emit_protocol_event/1}
        | children
      ]
    else
      children
    end
  end
end
