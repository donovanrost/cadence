defmodule Cadence.CCSDS.SDLP.AOS.Segmentation do
  @moduledoc """
  AOS profile segmentation service.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.Metrics

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def segment(%SDUOctets{profile: :aos}, ctx, state) do
    scope = Metrics.scope_from_ctx(ctx)
    Metrics.inc(scope, :aos, :segmentation_calls)
    Metrics.inc(scope, :aos, :segmentation_ok)
    {:ok, [], state}
  end

  def segment(_sdu, ctx, state) do
    scope = Metrics.scope_from_ctx(ctx)
    Metrics.inc(scope, :aos, :segmentation_calls)
    Metrics.inc(scope, :aos, :segmentation_error)
    {:error, :invalid_profile, state}
  end
end
