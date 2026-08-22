defmodule Cadence.TestSupport.CapturingTelemetryStorageWriter do
  @moduledoc false

  @behaviour Cadence.Telemetry.Storage.Writer

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_envelopes(envelopes, opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    send(test_pid, {:telemetry_storage_envelopes, envelopes})

    case Keyword.fetch(opts, :fail_with) do
      {:ok, reason} -> {:error, reason}
      :error -> :ok
    end
  end
end
