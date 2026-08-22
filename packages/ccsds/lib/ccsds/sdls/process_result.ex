defmodule CCSDS.SDLS.ProcessResult do
  @moduledoc """
  Successful ProcessSecurity return with clear Frame Data.
  """

  alias CCSDS.SDLS.Verification

  @type t :: %__MODULE__{
          data: binary(),
          security_header: binary(),
          security_trailer: binary(),
          spi: 1..65_534,
          initialization_vector: binary(),
          sequence_number: non_neg_integer() | nil,
          pad_length: non_neg_integer(),
          verification: Verification.t(),
          meta: map()
        }

  defstruct [
    :data,
    :security_header,
    :security_trailer,
    :spi,
    :initialization_vector,
    :sequence_number,
    :pad_length,
    :verification,
    meta: %{}
  ]
end
