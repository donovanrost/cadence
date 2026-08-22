defmodule CCSDS.SDLS.ApplyRequest do
  @moduledoc """
  ApplySecurity input for a partially formatted transfer frame.

  The frame prefix extends from the first primary-header octet through the
  octet immediately preceding the empty Security Header position.
  """

  alias CCSDS.SDLS.Channel

  @type t :: %__MODULE__{
          channel: Channel.t(),
          service: atom(),
          frame_prefix: binary(),
          data: binary(),
          meta: map()
        }

  defstruct [:channel, :service, :frame_prefix, :data, meta: %{}]
end
