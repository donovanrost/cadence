defmodule Cadence.TestSupport.FakeLogSink do
  @moduledoc false

  @behaviour Cadence.Telemetry.LogSink

  @impl true
  def append(shard_id, records, opts) do
    if notify = Keyword.get(opts, :notify) do
      send(notify, {:fake_log_sink_append, shard_id, records})
    end

    {:ok, %{first_offset: 0, last_offset: max(length(records) - 1, 0)}}
  end

  @impl true
  def partitions, do: {:ok, [0]}

  @impl true
  def health, do: {:ok, %{status: :ok}}
end
