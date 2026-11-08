defmodule Cadence.Runtime.MissionExecution do
  @moduledoc "Local, independently supervised contact and partition execution pools."
  use Supervisor

  alias Cadence.Runtime.MissionRuntime

  def start_link(opts) do
    namespace = Keyword.fetch!(opts, :process_namespace)
    mission_id = Keyword.fetch!(opts, :mission_id)

    Supervisor.start_link(__MODULE__, opts,
      name: MissionRuntime.execution_name(namespace, mission_id)
    )
  end

  @impl true
  def init(opts) do
    namespace = Keyword.fetch!(opts, :process_namespace)
    mission_id = Keyword.fetch!(opts, :mission_id)
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)

    children = [
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: MissionRuntime.realized_contact_supervisor_name(namespace, mission_id),
       extra_arguments: [runtime_opts]},
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: MissionRuntime.partition_supervisor_name(namespace, mission_id),
       extra_arguments: [runtime_opts]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
