defmodule Cadence.Runtime.TransportRecordsPersisted do
  @moduledoc "Data-plane fact emitted after transport runtime records commit."

  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord, TransportTimerEvent}

  @type t :: %__MODULE__{
          capability_records: [TransportCapabilityRecord.t()],
          action_requests: [TransportActionRequest.t()],
          timer_events: [TransportTimerEvent.t()],
          persisted_at: DateTime.t()
        }

  @enforce_keys [:capability_records, :action_requests, :timer_events, :persisted_at]
  defstruct @enforce_keys
end
