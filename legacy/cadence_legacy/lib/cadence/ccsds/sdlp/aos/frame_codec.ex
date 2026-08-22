defmodule Cadence.CCSDS.SDLP.AOS.FrameCodec do
  @moduledoc """
  AOS profile frame codec.
  """

  @behaviour Cadence.CCSDS.SDLP.FrameCodec

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.Metrics

  @impl true
  def profile, do: :aos

  @impl true
  def decode(bin, opts) when is_binary(bin) do
    scope = Metrics.scope_from_opts(opts)
    Metrics.inc(scope, profile(), :bytes_in, byte_size(bin))
    Metrics.inc(scope, profile(), :frame_decode_total)
    Metrics.inc(scope, profile(), :frame_decode_error)
    {:error, :not_implemented}
  end

  @impl true
  def encode(%LinkFrame{profile: :aos}, opts) do
    scope = Metrics.scope_from_opts(opts)
    Metrics.inc(scope, profile(), :frame_encode_total)
    Metrics.inc(scope, profile(), :frame_encode_error)
    {:error, :not_implemented}
  end

  def encode(_frame, opts) do
    scope = Metrics.scope_from_opts(opts)
    Metrics.inc(scope, profile(), :frame_encode_total)
    Metrics.inc(scope, profile(), :frame_encode_error)
    {:error, :invalid_profile}
  end
end
