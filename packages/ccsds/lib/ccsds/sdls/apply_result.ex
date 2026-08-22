defmodule CCSDS.SDLS.ApplyResult do
  @moduledoc """
  ApplySecurity return from Security Header through Security Trailer.
  """

  @type t :: %__MODULE__{
          payload: binary(),
          security_header: binary(),
          data: binary(),
          security_trailer: binary(),
          spi: 1..65_534,
          initialization_vector: binary(),
          sequence_number: non_neg_integer() | nil,
          pad_length: non_neg_integer(),
          meta: map()
        }

  defstruct [
    :payload,
    :security_header,
    :data,
    :security_trailer,
    :spi,
    :initialization_vector,
    :sequence_number,
    :pad_length,
    meta: %{}
  ]
end
