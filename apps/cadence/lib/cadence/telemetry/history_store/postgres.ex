defmodule Cadence.Telemetry.HistoryStore.Postgres do
  @moduledoc """
  Postgres-backed telemetry sample history.
  """

  @behaviour Cadence.Telemetry.HistoryStore

  alias Cadence.Telemetry.{EffectiveSelection, SourceFilters}
  alias Cadence.Telemetry.SampleRecords
  alias Cadence.Telemetry.Storage.ObservationIdentityStates

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_samples(samples) when is_list(samples) do
    SampleRecords.persist_samples(samples)
  end

  @impl true
  def sample_history(mission_id, point_id, opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)
    from_receipt_time = Keyword.get(opts, :from_receipt_time)
    to_receipt_time = Keyword.get(opts, :to_receipt_time)
    from_observed_at = Keyword.get(opts, :from_observed_at)
    to_observed_at = Keyword.get(opts, :to_observed_at)

    mission_id
    |> SampleRecords.list_samples(
      organization_id: Keyword.get(opts, :organization_id),
      point_id: point_id,
      spacecraft_id: spacecraft_id,
      from_receipt_time: from_receipt_time,
      to_receipt_time: to_receipt_time,
      from_observed_at: from_observed_at,
      to_observed_at: to_observed_at,
      order: order,
      time_axis: Keyword.get(opts, :time_axis)
    )
    |> SourceFilters.filter_samples(opts)
    |> EffectiveSelection.selected_samples(
      identity_rows_for_point(mission_id, point_id, opts),
      opts
    )
    |> Enum.take(limit)
  end

  @impl true
  def reset do
    SampleRecords.reset()
  end

  defp identity_rows_for_point(mission_id, point_id, opts) do
    ObservationIdentityStates.list_for_selection(mission_id,
      organization_id: Keyword.get(opts, :organization_id),
      point_id: point_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      realm: Keyword.get(opts, :realm),
      replay_run_id: SourceFilters.replay_run_id(opts),
      data_source_id: Keyword.get(opts, :data_source_id),
      binding_id: SourceFilters.binding_id(opts)
    )
  end
end
