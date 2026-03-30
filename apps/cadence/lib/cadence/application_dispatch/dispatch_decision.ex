defmodule Cadence.ApplicationDispatch.DispatchDecision do
  @moduledoc """
  Durable dispatch result for one packet record.
  """

  @type status :: :matched | :unmatched | :ambiguous

  @type t :: %__MODULE__{
          dispatch_decision_id: binary(),
          packet_id: binary(),
          evidence_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          status: status(),
          matched_rule_ids: [binary()],
          anomalies: [term()],
          work_items: [Cadence.ApplicationDispatch.WorkItem.t()]
        }

  defstruct [
    :dispatch_decision_id,
    :packet_id,
    :evidence_id,
    :binding_set_id,
    :binding_set_version,
    :status,
    matched_rule_ids: [],
    anomalies: [],
    work_items: []
  ]
end
