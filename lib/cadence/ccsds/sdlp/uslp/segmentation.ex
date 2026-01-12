defmodule Cadence.CCSDS.SDLP.USLP.Segmentation do
  @moduledoc """
  USLP profile segmentation service.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.SDUOctets

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def segment(%SDUOctets{profile: :uslp}, _ctx, state), do: {:ok, [], state}
  def segment(_sdu, _ctx, state), do: {:error, :invalid_profile, state}
end
