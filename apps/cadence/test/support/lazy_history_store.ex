defmodule Cadence.TestSupport.LazyHistoryStore do
  @moduledoc false

  @behaviour Cadence.Telemetry.HistoryStore

  def child_spec(_opts), do: nil

  def persist_samples(_samples), do: :ok

  def sample_history(_mission_id, _point_id, _opts), do: []

  def reset, do: :ok
end
