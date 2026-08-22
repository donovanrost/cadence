defmodule Cadence.Telemetry.Storage.Writers.Noop do
  @moduledoc """
  Telemetry storage writer that accepts envelopes without persisting them.
  """

  @behaviour Cadence.Telemetry.Storage.Writer

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_envelopes(_envelopes, _opts), do: :ok
end
