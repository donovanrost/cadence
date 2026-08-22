defmodule Cadence.CCSDS.SDLS.Verification do
  @moduledoc """
  ProcessSecurity verification status and portable failure evidence.
  """

  @type code ::
          :no_failure
          | :invalid_spi
          | :mac_verification_failure
          | :anti_replay_sequence_number_failure
          | :padding_error
          | :malformed_security_header
          | :cryptographic_failure

  @type t :: %__MODULE__{
          status: :success | :failure,
          code: code(),
          reason: term(),
          spi: non_neg_integer() | nil
        }

  defstruct status: :success, code: :no_failure, reason: nil, spi: nil
end
