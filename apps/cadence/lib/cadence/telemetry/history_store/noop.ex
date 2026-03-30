defmodule Cadence.Telemetry.HistoryStore.Noop do
  @moduledoc """
  History backend that discards samples and returns no history.
  """

  @behaviour Cadence.Telemetry.HistoryStore

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_samples(_samples), do: :ok

  @impl true
  def sample_history(_mission_id, _point_id, _opts), do: []

  @impl true
  def reset, do: :ok
end
