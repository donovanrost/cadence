defmodule Cadence.CCSDS.SDLS.Operation do
  @moduledoc """
  Algorithm-neutral context passed to an SDLS crypto provider.
  """

  alias Cadence.CCSDS.SDLS.{Channel, SecurityAssociation}

  @type t :: %__MODULE__{
          direction: :outbound | :inbound,
          channel: Channel.t(),
          service: atom(),
          association: SecurityAssociation.t(),
          frame_prefix: binary(),
          security_header: binary(),
          initialization_vector: binary(),
          sequence_number: non_neg_integer() | nil,
          pad_length: non_neg_integer(),
          meta: map()
        }

  defstruct [
    :direction,
    :channel,
    :service,
    :association,
    :frame_prefix,
    :security_header,
    :initialization_vector,
    :sequence_number,
    :pad_length,
    meta: %{}
  ]
end
