defmodule Cadence.Catalog.Events do
  @moduledoc """
  PubSub topic helpers and lifecycle broadcast helpers for catalog import runs.

  The catalog subsystem is the only authority for these topic names — nothing
  else should construct them by hand.
  """

  alias Cadence.Catalog.ImportRun

  @pubsub Cadence.PubSub

  @spec import_runs_topic(binary()) :: binary()
  def import_runs_topic(mission_id) when is_binary(mission_id) do
    "catalog:mission:#{mission_id}:import_runs"
  end

  @spec import_run_topic(binary(), binary()) :: binary()
  def import_run_topic(mission_id, import_run_id)
      when is_binary(mission_id) and is_binary(import_run_id) do
    "catalog:mission:#{mission_id}:import_run:#{import_run_id}"
  end

  @spec subscribe_import_runs(binary()) :: :ok | {:error, term()}
  def subscribe_import_runs(mission_id) when is_binary(mission_id) do
    Phoenix.PubSub.subscribe(@pubsub, import_runs_topic(mission_id))
  end

  @spec subscribe_import_run(binary(), binary()) :: :ok | {:error, term()}
  def subscribe_import_run(mission_id, import_run_id)
      when is_binary(mission_id) and is_binary(import_run_id) do
    Phoenix.PubSub.subscribe(@pubsub, import_run_topic(mission_id, import_run_id))
  end

  @spec broadcast_started(ImportRun.t()) :: :ok
  def broadcast_started(%ImportRun{} = run), do: broadcast(run, :import_run_started)

  @spec broadcast_updated(ImportRun.t()) :: :ok
  def broadcast_updated(%ImportRun{} = run), do: broadcast(run, :import_run_updated)

  @spec broadcast_completed(ImportRun.t()) :: :ok
  def broadcast_completed(%ImportRun{} = run), do: broadcast(run, :import_run_completed)

  @spec broadcast_failed(ImportRun.t()) :: :ok
  def broadcast_failed(%ImportRun{} = run), do: broadcast(run, :import_run_failed)

  defp broadcast(%ImportRun{mission_id: mission_id, import_run_id: run_id} = run, event) do
    message = {event, run}
    :ok = Phoenix.PubSub.broadcast(@pubsub, import_runs_topic(mission_id), message)
    :ok = Phoenix.PubSub.broadcast(@pubsub, import_run_topic(mission_id, run_id), message)
    :ok
  end
end
