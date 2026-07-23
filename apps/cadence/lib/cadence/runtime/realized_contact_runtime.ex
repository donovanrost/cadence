defmodule Cadence.Runtime.RealizedContactRuntime do
  @moduledoc false

  use Supervisor

  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  def start_link(%RealizedContactRuntimeSpec{} = realized_contact) do
    Supervisor.start_link(
      __MODULE__,
      realized_contact,
      name:
        MissionRuntime.realized_contact_runtime_name(
          realized_contact.mission_id,
          realized_contact.realized_contact_id
        )
    )
  end

  @impl true
  def init(%RealizedContactRuntimeSpec{} = realized_contact) do
    children = [
      {DynamicSupervisor,
       strategy: :one_for_one,
       name:
         MissionRuntime.path_supervisor_name(
           realized_contact.mission_id,
           realized_contact.realized_contact_id
         )},
      {Cadence.Runtime.DownlinkCombiner, realized_contact: realized_contact},
      {Cadence.Runtime.ContactCoordinator, realized_contact: realized_contact}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
