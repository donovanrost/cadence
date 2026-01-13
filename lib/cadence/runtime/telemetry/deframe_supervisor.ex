defmodule Cadence.Runtime.Telemetry.DeframeSupervisor do
  @moduledoc """
  Dynamic supervisor for per-stream deframe workers.
  """

  alias Cadence.Runtime.Telemetry.DeframeWorker

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)
    name = via_tuple(mission_id, interface_id)
    DynamicSupervisor.start_link(strategy: :one_for_one, name: name)
  end

  def child_spec(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)

    %{
      id: {:deframe_supervisor, mission_id, interface_id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_worker(mission_id, interface_id, connection_id, profile, scid, vcid, opts) do
    name = worker_name(mission_id, interface_id, connection_id, profile, scid, vcid)

    child_spec =
      {DeframeWorker,
       Keyword.merge(opts,
         name: name,
         mission_id: mission_id,
         interface_id: interface_id,
         connection_id: connection_id,
         profile: profile,
         scid: scid,
         vcid: vcid
       )}

    DynamicSupervisor.start_child(via_tuple(mission_id, interface_id), child_spec)
  end

  def via_tuple(mission_id, interface_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:deframe_supervisor, mission_id, interface_id}}}
  end

  def worker_name(mission_id, interface_id, connection_id, profile, scid, vcid) do
    {:via, Registry,
     {Cadence.MissionRegistry,
      {:deframe_worker, mission_id, interface_id, connection_id, profile, scid, vcid}}}
  end
end
