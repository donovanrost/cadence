defmodule Cadence.CCSDS.CFDP.UserOperation.ProxyPutResponse do
  @moduledoc "Typed Proxy Put Response reserved message."

  alias Cadence.CCSDS.CFDP

  @type file_status :: :discarded_deliberately | :discarded_by_filestore | :retained | :unreported

  @type t :: %__MODULE__{
          condition: CFDP.condition(),
          delivery_code: :complete | :incomplete,
          file_status: file_status()
        }

  defstruct condition: :no_error, delivery_code: :complete, file_status: :unreported
end
