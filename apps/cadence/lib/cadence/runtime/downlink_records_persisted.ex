defmodule Cadence.Runtime.DownlinkRecordsPersisted do
  @moduledoc "Data-plane fact emitted after downlink combiner records commit."

  alias Cadence.Contacts.{CombinedDownlinkRecord, DownlinkDiagnostic, DownlinkObservation}

  @type t :: %__MODULE__{
          observations: [DownlinkObservation.t()],
          combined_records: [CombinedDownlinkRecord.t()],
          diagnostics: [DownlinkDiagnostic.t()],
          persisted_at: DateTime.t()
        }

  @enforce_keys [:observations, :combined_records, :diagnostics, :persisted_at]
  defstruct @enforce_keys
end
