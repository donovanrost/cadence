defmodule Cadence.Runtime.ManagedRecordsPersisted do
  @moduledoc "Data-plane fact emitted after managed runtime records commit."

  alias Cadence.Runtime.{ManagedActionRequest, ManagedCapabilityRecord, ManagedTimerEvent}

  @type t :: %__MODULE__{
          capability_records: [ManagedCapabilityRecord.t()],
          action_requests: [ManagedActionRequest.t()],
          timer_events: [ManagedTimerEvent.t()],
          persisted_at: DateTime.t()
        }

  @enforce_keys [:capability_records, :action_requests, :timer_events, :persisted_at]
  defstruct @enforce_keys
end
