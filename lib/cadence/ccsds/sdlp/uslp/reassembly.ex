defmodule Cadence.CCSDS.SDLP.USLP.Reassembly do
  @moduledoc """
  USLP profile reassembly service.
  """

  @behaviour Cadence.CCSDS.SDLP.Reassembly

  alias Cadence.CCSDS.Core.LinkFrame

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def ingest(%LinkFrame{profile: :uslp}, _ctx, state), do: {:ok, [], state}
  def ingest(_frame, _ctx, state), do: {:error, :invalid_profile, state}
end
