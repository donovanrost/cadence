defmodule Cadence.CCSDS.SDLP.USLP.Reassembly do
  @moduledoc """
  USLP profile reassembly service.
  """

  @behaviour Cadence.CCSDS.SDLP.Reassembly

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.Metrics

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def ingest(%LinkFrame{profile: :uslp}, ctx, state) do
    scope = Metrics.scope_from_ctx(ctx)
    Metrics.inc(scope, :uslp, :reassembly_calls)
    Metrics.inc(scope, :uslp, :reassembly_ok)
    {:ok, [], state}
  end

  def ingest(_frame, ctx, state) do
    scope = Metrics.scope_from_ctx(ctx)
    Metrics.inc(scope, :uslp, :reassembly_calls)
    Metrics.inc(scope, :uslp, :reassembly_error)
    {:error, :invalid_profile, state}
  end
end
