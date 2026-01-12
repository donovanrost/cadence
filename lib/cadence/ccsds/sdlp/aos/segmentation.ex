defmodule Cadence.CCSDS.SDLP.AOS.Segmentation do
  @moduledoc """
  AOS profile segmentation service.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.SDUOctets

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def segment(%SDUOctets{profile: :aos}, _ctx, state), do: {:ok, [], state}
  def segment(_sdu, _ctx, state), do: {:error, :invalid_profile, state}
end
