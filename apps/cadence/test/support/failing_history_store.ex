defmodule Cadence.TestSupport.FailingHistoryStore do
  @moduledoc false

  @behaviour Cadence.Telemetry.HistoryStore

  def child_spec(_opts), do: nil

  def persist_samples(_samples), do: :ok

  def sample_history(_mission_id, _point_id, _opts), do: []

  def sample_history_result(_mission_id, _point_id, opts) do
    {:error, Keyword.get(opts, :failure_reason, :source_unavailable)}
  end

  def reset, do: :ok
end
