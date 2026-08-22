defmodule Cadence.Telemetry.LogSink.Noop do
  @moduledoc """
  No-op sink useful for development and tests.
  """

  @behaviour Cadence.Telemetry.LogSink

  @impl true
  def append(_shard_id, _records, _opts), do: {:ok, %{first_offset: 0, last_offset: 0}}

  @impl true
  def partitions, do: {:ok, []}

  @impl true
  def health, do: {:ok, %{status: :ok}}
end
