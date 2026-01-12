defmodule Cadence.CCSDS.Core.Types do
  @moduledoc """
  Shared CCSDS types for core artifacts.
  """

  @type profile :: :tm | :aos | :uslp
  @type direction :: :uplink | :downlink
  @type quality :: :good | :suspect | :invalid
  @type map_id :: non_neg_integer() | nil
  @type vcid :: non_neg_integer()
  @type scid :: non_neg_integer()
  @type frame_seq :: non_neg_integer() | nil
  @type timestamp :: DateTime.t() | nil
end
