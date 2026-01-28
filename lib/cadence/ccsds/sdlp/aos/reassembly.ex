defmodule Cadence.CCSDS.SDLP.AOS.Reassembly do
  @moduledoc """
  AOS profile reassembly service.
  """

  @behaviour Cadence.CCSDS.SDLP.Reassembly

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.Metrics

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def ingest(%LinkFrame{profile: :aos}, ctx, state) do
    scope = Metrics.scope_from_ctx(ctx)
    Metrics.inc(scope, :aos, :reassembly_calls)
    Metrics.inc(scope, :aos, :reassembly_ok)
    {:ok, [], state}
  end

  def ingest(_frame, ctx, state) do
    scope = Metrics.scope_from_ctx(ctx)
    Metrics.inc(scope, :aos, :reassembly_calls)
    Metrics.inc(scope, :aos, :reassembly_error)
    {:error, :invalid_profile, state}
  end
end
