defmodule Cadence.TestSupport.FailingHistoryStore do
  @moduledoc false

  @behaviour Cadence.Telemetry.HistoryStore

  def child_spec(_opts), do: nil

  def persist_samples(_samples), do: :ok

  def sample_history(_mission_id, _point_id, _opts), do: []

  def sample_history_result(_mission_id, _point_id, _opts) do
    {:error, failure_reason()}
  end

  def reset, do: :ok

  defp failure_reason do
    :cadence
    |> Application.get_env(:telemetry_history_store, [])
    |> Keyword.get(:failure_reason, :source_unavailable)
  end
end
