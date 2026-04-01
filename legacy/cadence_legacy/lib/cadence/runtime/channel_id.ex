defmodule Cadence.Runtime.ChannelId do
  @moduledoc """
  Canonical CCSDS channel identity used by protocol layers.

  This is the stable identity for protocol state and survives interface churn.
  """

  @type t :: %__MODULE__{
          scid: non_neg_integer(),
          vcid: non_neg_integer(),
          map_id: non_neg_integer() | nil
        }

  @enforce_keys [:scid, :vcid]
  defstruct [:scid, :vcid, :map_id]

  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer() | nil) :: t()
  def new(scid, vcid, map_id \\ nil)
      when is_integer(scid) and scid >= 0 and is_integer(vcid) and vcid >= 0 do
    %__MODULE__{scid: scid, vcid: vcid, map_id: map_id}
  end

  @spec key(t()) :: {non_neg_integer(), non_neg_integer(), non_neg_integer() | nil}
  def key(%__MODULE__{scid: scid, vcid: vcid, map_id: map_id}) do
    {scid, vcid, map_id}
  end
end
