defmodule Cadence.Control.Replay.Store do
  @moduledoc """
  Control-plane persistence and query boundary for replay runs and outputs.
  """

  import Ecto.Query

  alias Cadence.Control.Replay.Store.{
    ReplayManagedActionRequestRow,
    ReplayManagedCapabilityRecordRow,
    ReplayManagedTimerEventRow,
    ReplayRunRow,
    ReplayTelemetrySampleRow
  }

  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.Runtime.{ManagedActionRequest, ManagedCapabilityRecord, ManagedTimerEvent}
  alias Cadence.Telemetry.Sample

  @spec list_runs(binary(), binary(), keyword()) :: [Run.t()]
  def list_runs(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 25)
    order = Keyword.get(opts, :order, :desc)

    ReplayRunRow
    |> where(
      [replay_run],
      replay_run.organization_id == ^organization_id and replay_run.mission_id == ^mission_id
    )
    |> order_replay_runs(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ReplayRunRow.to_domain/1)
  end

  @spec fetch_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def fetch_run(replay_run_id) when is_binary(replay_run_id) do
    case Repo.get(ReplayRunRow, replay_run_id) do
      nil -> {:error, :replay_run_not_found}
      %ReplayRunRow{} = replay_run_row -> {:ok, ReplayRunRow.to_domain(replay_run_row)}
    end
  end

  @spec telemetry_samples(binary(), keyword()) :: [Sample.t()]
  def telemetry_samples(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 1_000)
    order = Keyword.get(opts, :order, :asc)

    ReplayTelemetrySampleRow
    |> where([sample_row], sample_row.replay_run_id == ^replay_run_id)
    |> order_replay_samples(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ReplayTelemetrySampleRow.to_domain/1)
  end

  @doc false
  @spec telemetry_comparison_samples(binary()) :: [map()]
  def telemetry_comparison_samples(replay_run_id) when is_binary(replay_run_id) do
    ReplayTelemetrySampleRow
    |> where([sample_row], sample_row.replay_run_id == ^replay_run_id)
    |> order_by([sample_row],
      asc: sample_row.evidence_id,
      asc: sample_row.point_id,
      asc: sample_row.sample_id
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      sample = ReplayTelemetrySampleRow.to_domain(row)

      %{
        evidence_id: sample.evidence_id,
        point_id: sample.point_id,
        sample_id: sample.sample_id,
        raw_value: sample.raw_value,
        engineering_value: sample.engineering_value,
        quality_state: Atom.to_string(sample.quality_state)
      }
    end)
  end

  @spec managed_capability_records(binary(), keyword()) :: [ManagedCapabilityRecord.t()]
  def managed_capability_records(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 1_000)
    order = Keyword.get(opts, :order, :asc)

    ReplayManagedCapabilityRecordRow
    |> where([row], row.replay_run_id == ^replay_run_id)
    |> order_managed_capability_records(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ReplayManagedCapabilityRecordRow.to_domain/1)
  end

  @spec managed_action_requests(binary(), keyword()) :: [ManagedActionRequest.t()]
  def managed_action_requests(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 1_000)
    order = Keyword.get(opts, :order, :asc)

    ReplayManagedActionRequestRow
    |> where([row], row.replay_run_id == ^replay_run_id)
    |> order_managed_action_requests(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ReplayManagedActionRequestRow.to_domain/1)
  end

  @spec managed_timer_events(binary(), keyword()) :: [ManagedTimerEvent.t()]
  def managed_timer_events(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 1_000)
    order = Keyword.get(opts, :order, :asc)

    ReplayManagedTimerEventRow
    |> where([row], row.replay_run_id == ^replay_run_id)
    |> order_managed_timer_events(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ReplayManagedTimerEventRow.to_domain/1)
  end

  defp order_replay_samples(query, :desc) do
    order_by(query, [sample_row], desc: sample_row.receipt_time, desc: sample_row.sample_id)
  end

  defp order_replay_samples(query, _order) do
    order_by(query, [sample_row], asc: sample_row.receipt_time, asc: sample_row.sample_id)
  end

  defp order_replay_runs(query, :asc) do
    order_by(query, [replay_run],
      asc: replay_run.started_at,
      asc: replay_run.inserted_at,
      asc: replay_run.replay_run_id
    )
  end

  defp order_replay_runs(query, _order) do
    order_by(query, [replay_run],
      desc: replay_run.started_at,
      desc: replay_run.inserted_at,
      desc: replay_run.replay_run_id
    )
  end

  defp order_managed_capability_records(query, :desc) do
    order_by(query, [row], desc: row.recorded_at, desc: row.capability_record_id)
  end

  defp order_managed_capability_records(query, _order) do
    order_by(query, [row], asc: row.recorded_at, asc: row.capability_record_id)
  end

  defp order_managed_action_requests(query, :desc) do
    order_by(query, [row], desc: row.requested_at, desc: row.action_request_id)
  end

  defp order_managed_action_requests(query, _order) do
    order_by(query, [row], asc: row.requested_at, asc: row.action_request_id)
  end

  defp order_managed_timer_events(query, :desc) do
    order_by(query, [row], desc: row.occurred_at, desc: row.timer_event_id)
  end

  defp order_managed_timer_events(query, _order) do
    order_by(query, [row], asc: row.occurred_at, asc: row.timer_event_id)
  end
end
