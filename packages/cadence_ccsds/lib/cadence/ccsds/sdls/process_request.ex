defmodule Cadence.CCSDS.SDLS.ProcessRequest do
  @moduledoc """
  ProcessSecurity input for a received partial transfer frame.

  The secured payload begins with the Security Header and ends with the
  optional Security Trailer.
  """

  alias Cadence.CCSDS.SDLS.Channel

  @type t :: %__MODULE__{
          channel: Channel.t(),
          service: atom(),
          frame_prefix: binary(),
          secured_payload: binary(),
          meta: map()
        }

  defstruct [:channel, :service, :frame_prefix, :secured_payload, meta: %{}]
end
