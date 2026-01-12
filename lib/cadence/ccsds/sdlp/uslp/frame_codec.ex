defmodule Cadence.CCSDS.SDLP.USLP.FrameCodec do
  @moduledoc """
  USLP profile frame codec.
  """

  @behaviour Cadence.CCSDS.SDLP.FrameCodec

  alias Cadence.CCSDS.Core.LinkFrame

  @impl true
  def profile, do: :uslp

  @impl true
  def decode(_bin, _opts), do: {:error, :not_implemented}

  @impl true
  def encode(%LinkFrame{profile: :uslp}, _opts), do: {:error, :not_implemented}
  def encode(_frame, _opts), do: {:error, :invalid_profile}
end
