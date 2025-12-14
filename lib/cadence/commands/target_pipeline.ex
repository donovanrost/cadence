defmodule Cadence.Commands.TargetPipeline do
  @moduledoc """
  Supervisor for a single target's command queue and dispatcher.

  Each target gets its own TargetPipeline which supervises:
  - TargetQueue - manages command ordering and scheduling
  - TargetDispatcher - handles command execution

  This 1:1 relationship ensures:
  - Clean separation of concerns
  - Per-target command serialization (safety)
  - Cross-target parallelism (performance)
  - Isolated failure domains

  ## Example

      # Started by TargetPipelineSupervisor
      {:ok, pid} = TargetPipeline.start_link(mission_id: mission_id, target_id: target_id)

      # Find the pipeline process
      pid = TargetPipeline.whereis(mission_id, target_id)
  """

  use Supervisor

  require Logger

  alias Cadence.Commands.{TargetQueue, TargetDispatcher}

  @registry Cadence.MissionRegistry

  ## Client API

  @doc """
  Starts the pipeline for a target.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    target_id = Keyword.fetch!(opts, :target_id)

    Supervisor.start_link(__MODULE__, {mission_id, target_id},
      name: via_tuple(mission_id, target_id)
    )
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via_tuple(mission_id, target_id) do
    {:via, Registry, {@registry, {:target_pipeline, mission_id, target_id}}}
  end

  @doc """
  Returns the PID of a pipeline by mission_id and target_id.
  """
  def whereis(mission_id, target_id) do
    case Registry.lookup(@registry, {:target_pipeline, mission_id, target_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  ## Supervisor Callbacks

  @impl true
  def init({mission_id, target_id}) do
    Logger.info(
      "Starting TargetPipeline for mission_id=#{mission_id}, target_id=#{target_id}"
    )

    children = [
      # Queue must start before Dispatcher since Dispatcher queries Queue
      {TargetQueue, mission_id: mission_id, target_id: target_id},
      {TargetDispatcher, mission_id: mission_id, target_id: target_id}
    ]

    # one_for_one: if queue crashes, restart just queue
    # if dispatcher crashes, restart just dispatcher
    # They can recover independently
    Supervisor.init(children, strategy: :one_for_one)
  end
end
