defmodule Cadence.Runtime.PathRuntime do
  @moduledoc false

  use Supervisor

  alias Cadence.Runtime.{ContactPathSpec, MissionRuntime}

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.fetch!(opts, :realized_contact_id)
    %ContactPathSpec{} = path = Keyword.fetch!(opts, :path)

    Supervisor.start_link(
      __MODULE__,
      opts,
      name: MissionRuntime.path_runtime_name(mission_id, realized_contact_id, path.path_id)
    )
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.fetch!(opts, :realized_contact_id)
    %ContactPathSpec{} = path = Keyword.fetch!(opts, :path)

    children = [
      {DynamicSupervisor,
       strategy: :one_for_one,
       name:
         MissionRuntime.transport_supervisor_name(mission_id, realized_contact_id, path.path_id)},
      {DynamicSupervisor,
       strategy: :one_for_one,
       name:
         MissionRuntime.provider_supervisor_name(mission_id, realized_contact_id, path.path_id)},
      {Cadence.Runtime.PathCoordinator, opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
