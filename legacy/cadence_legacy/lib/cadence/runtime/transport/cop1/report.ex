defmodule Cadence.Runtime.Transport.COP1.Report do
  @moduledoc """
  Normalized COP-1 report payload bound to a TC stream.
  """

  alias Cadence.Transport.TCStreamId

  @type status :: :accept | :reject | :lockout | :wait | :retransmit

  @type t :: %__MODULE__{
          tc_stream_id: TCStreamId.t(),
          seq: non_neg_integer() | nil,
          status: status(),
          raw: term() | nil
        }

  @enforce_keys [:tc_stream_id, :status]
  defstruct [
    :tc_stream_id,
    :seq,
    :status,
    :raw
  ]
end
