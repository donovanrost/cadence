defmodule Cadence.Telemetry.HistoryStore.QuestDB do
  @moduledoc """
  QuestDB-backed telemetry history reader.

  Writes flow through `Cadence.Telemetry.Storage`; this module bridges the
  existing history read behaviour to the managed QuestDB observations table.
  """

  @behaviour Cadence.Telemetry.HistoryStore

  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.QuestDB.ObservationReader

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_samples(samples) when is_list(samples) do
    Storage.persist_samples(samples)
  end

  def persist_samples(samples, opts) when is_list(samples) and is_list(opts) do
    Storage.persist_samples(Keyword.fetch!(opts, :storage_policy), samples, [])
  end

  @impl true
  def sample_history(mission_id, point_id, opts) do
    ObservationReader.sample_history(mission_id, point_id, opts)
  end

  @impl true
  def sample_history_result(mission_id, point_id, opts) do
    ObservationReader.sample_history_result(mission_id, point_id, opts)
  end

  @impl true
  def decimated_sample_history_result(mission_id, point_id, opts) do
    ObservationReader.decimated_history_result(mission_id, point_id, opts)
  end

  @impl true
  def sample_watermark_result(mission_id, point_id, opts) do
    ObservationReader.sample_watermark_result(mission_id, point_id, opts)
  end

  @impl true
  def reset, do: :ok
end
