defmodule Cadence.Telemetry.ResolvedUnit do
  @moduledoc """
  Resolution result attaching identity and schema to a parsed unit.
  """

  @type identity_result ::
          {:ok, binary()}
          | {:unresolved, reason :: atom() | term(), evidence_hint :: term() | nil}
          | {:ambiguous, candidates :: [{binary(), score :: float()}],
             evidence_hint :: term() | nil}

  @type schema_result ::
          {:ok, term()}
          | {:uncataloged_target, binary()}
          | {:unknown_apid, binary(), term(), non_neg_integer()}
          | {:schema_unavailable, term()}
          | {:unsupported_format, atom()}

  @type t :: %__MODULE__{
          packet_id: binary(),
          mission_id: binary(),
          envelope: Cadence.Telemetry.PacketEnvelope.t(),
          parsed_unit: Cadence.Telemetry.ParsedUnit.t(),
          format: :space_packet | :encap_packet | :unknown,
          identity: identity_result(),
          schema: schema_result(),
          decision_trace: map(),
          config_version_used: non_neg_integer()
        }

  defstruct [
    :packet_id,
    :mission_id,
    :envelope,
    :parsed_unit,
    :format,
    :identity,
    :schema,
    :config_version_used,
    decision_trace: %{}
  ]
end
