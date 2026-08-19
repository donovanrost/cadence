defmodule Cadence.Runtime.RealizedContactRuntime do
  @moduledoc false

  use Supervisor

  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  def start_link(%RealizedContactRuntimeSpec{} = realized_contact) do
    start_link([], realized_contact)
  end

  def start_link(runtime_opts, %RealizedContactRuntimeSpec{} = realized_contact)
      when is_list(runtime_opts) do
    process_namespace = process_namespace(runtime_opts)

    Supervisor.start_link(
      __MODULE__,
      {realized_contact, runtime_opts},
      name:
        MissionRuntime.realized_contact_runtime_name(
          process_namespace,
          realized_contact.mission_id,
          realized_contact.realized_contact_id
        )
    )
  end

  @impl true
  def init({%RealizedContactRuntimeSpec{} = realized_contact, runtime_opts})
      when is_list(runtime_opts) do
    process_namespace = process_namespace(runtime_opts)

    children = [
      {DynamicSupervisor,
       strategy: :one_for_one,
       name:
         MissionRuntime.path_supervisor_name(
           process_namespace,
           realized_contact.mission_id,
           realized_contact.realized_contact_id
         ),
       extra_arguments: [runtime_opts]},
      {Task.Supervisor,
       name:
         MissionRuntime.realized_contact_quiescence_supervisor_name(
           process_namespace,
           realized_contact.mission_id,
           realized_contact.realized_contact_id
         )},
      {Cadence.Runtime.DownlinkCombiner,
       realized_contact: realized_contact, process_namespace: process_namespace},
      {Cadence.Runtime.ContactCoordinator,
       realized_contact: realized_contact, process_namespace: process_namespace}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def init(%RealizedContactRuntimeSpec{} = realized_contact), do: init({realized_contact, []})

  defp process_namespace(runtime_opts) do
    Keyword.get_lazy(runtime_opts, :process_namespace, &ProcessNamespace.default/0)
  end
end
