defmodule Cadence.CCSDS.SDLP.AOS.FrameCodec do
  @moduledoc """
  AOS profile frame codec.
  """

  @behaviour Cadence.CCSDS.SDLP.FrameCodec

  alias Cadence.CCSDS.Core.LinkFrame

  @impl true
  def profile, do: :aos

  @impl true
  def decode(_bin, _opts), do: {:error, :not_implemented}

  @impl true
  def encode(%LinkFrame{profile: :aos}, _opts), do: {:error, :not_implemented}
  def encode(_frame, _opts), do: {:error, :invalid_profile}
end
