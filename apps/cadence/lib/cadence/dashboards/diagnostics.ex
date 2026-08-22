defmodule Cadence.Dashboards.Diagnostics do
  @moduledoc """
  Dashboard execution semantics and durable runtime diagnostic evidence.
  """

  alias Cadence.Dashboards.{DashboardResolveResult, SourceExecutionSemantics}

  alias Cadence.Dashboards.RuntimeInvalidation.{
    DecisionEvent,
    DecisionEvents,
    DecisionProjection,
    Event
  }

  alias Cadence.Reads.OperationalEvidence

  def summarize_source_execution(%DashboardResolveResult{} = result),
    do: SourceExecutionSemantics.summarize(result)

  def source_capability_posture_events(%DashboardResolveResult{} = result, opts \\ []),
    do: SourceExecutionSemantics.source_capability_posture_events(result, opts)

  def record_source_capability_postures(%DashboardResolveResult{} = result, opts \\ []) do
    result
    |> source_capability_posture_events(opts)
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, events} ->
      case Cadence.OperationalEvents.persist_event(event) do
        {:ok, persisted_event} -> {:cont, {:ok, [persisted_event | events]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_source_capability_posture_events(organization_id, mission_id, opts \\ []) do
    OperationalEvidence.list_operational_events(
      organization_id,
      mission_id,
      Keyword.merge(opts,
        category: :data_source,
        source_record_kind: :source_capability_posture
      )
    )
  end

  @spec runtime_invalidation_decisions(map() | [map()], keyword()) :: [
          DecisionProjection.decision_row()
        ]
  def runtime_invalidation_decisions(snapshot_or_recent_events, opts \\ []),
    do: DecisionProjection.list(snapshot_or_recent_events, opts)

  @spec record_runtime_invalidation_decision(Event.t(), map(), keyword()) ::
          {:ok, DecisionEvent.t()} | {:error, term()}
  def record_runtime_invalidation_decision(%Event{} = event, decision, opts \\ []),
    do: DecisionEvents.record(event, decision, opts)

  @spec durable_runtime_invalidation_decisions(keyword()) :: [
          DecisionProjection.decision_row()
        ]
  def durable_runtime_invalidation_decisions(opts \\ []),
    do: DecisionEvents.list_decision_rows(opts)
end
