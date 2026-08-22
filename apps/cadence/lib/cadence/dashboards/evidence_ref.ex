defmodule Cadence.Dashboards.EvidenceRef do
  @moduledoc """
  Stable pointer to data or operational evidence behind a dashboard result.
  """

  alias Cadence.Platform.ContractNormalization

  @kinds [
    :raw_evidence,
    :telemetry_sample,
    :limit_event,
    :limit_definition,
    :limit_definition_interval,
    :limit_definition_lifecycle_event,
    :mission_event,
    :operational_event,
    :operational_interval,
    :binding_set_interval,
    :application_binding_interval,
    :catalog_revision_interval,
    :source_binding_interval,
    :source_health_interval,
    :transport_execution_interval,
    :transport_connection_state_interval,
    :ground_station_connection_state_interval,
    :ground_station_antenna_pointing_state_interval,
    :link_rf_lock_state_interval,
    :link_frame_sync_state_interval,
    :source_health_event,
    :source_watermark_event,
    :source_binding_event,
    :command_queue_entry,
    :command_release_attempt,
    :command_verifier_instance,
    :transport_action_request,
    :transport_capability_record,
    :telemetry_revision_decision_event,
    :telemetry_backfill_lifecycle_event,
    :contact,
    :scheduled_contact,
    :realized_contact,
    :source_request,
    :data_source,
    :source_binding
  ]

  @sources [:telemetry, :limits, :events, :operational_observables]
  @confidences [:direct, :projected, :derived, :best_effort]

  @type kind ::
          :raw_evidence
          | :telemetry_sample
          | :limit_event
          | :limit_definition
          | :limit_definition_interval
          | :limit_definition_lifecycle_event
          | :mission_event
          | :operational_event
          | :operational_interval
          | :binding_set_interval
          | :application_binding_interval
          | :catalog_revision_interval
          | :source_binding_interval
          | :source_health_interval
          | :transport_execution_interval
          | :transport_connection_state_interval
          | :ground_station_connection_state_interval
          | :ground_station_antenna_pointing_state_interval
          | :link_rf_lock_state_interval
          | :link_frame_sync_state_interval
          | :source_health_event
          | :source_watermark_event
          | :source_binding_event
          | :command_queue_entry
          | :command_release_attempt
          | :command_verifier_instance
          | :transport_action_request
          | :transport_capability_record
          | :telemetry_revision_decision_event
          | :telemetry_backfill_lifecycle_event
          | :contact
          | :scheduled_contact
          | :realized_contact
          | :source_request
          | :data_source
          | :source_binding

  @type confidence :: :direct | :projected | :derived | :best_effort
  @type source :: :telemetry | :limits | :events | :operational_observables

  @type t :: %__MODULE__{
          kind: kind(),
          id: binary(),
          observed_at: DateTime.t() | nil,
          source: source(),
          confidence: confidence()
        }

  defstruct [:kind, :id, :observed_at, :source, confidence: :direct]

  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @spec kind?(term()) :: boolean()
  def kind?(kind), do: kind in @kinds

  @spec sources() :: [source()]
  def sources, do: @sources

  @spec source?(term()) :: boolean()
  def source?(source), do: source in @sources

  @spec confidences() :: [confidence()]
  def confidences, do: @confidences

  @spec confidence?(term()) :: boolean()
  def confidence?(confidence), do: confidence in @confidences

  @spec normalize(term()) :: t() | nil
  def normalize(%__MODULE__{} = ref), do: ref

  def normalize(ref) when is_map(ref) do
    %__MODULE__{
      kind: ref |> ContractNormalization.attr(:kind) |> ContractNormalization.known_atom(@kinds),
      id: ContractNormalization.attr(ref, :id),
      observed_at: ContractNormalization.attr(ref, :observed_at),
      source:
        ref |> ContractNormalization.attr(:source) |> ContractNormalization.known_atom(@sources),
      confidence:
        ref
        |> ContractNormalization.attr(:confidence, :direct)
        |> ContractNormalization.known_atom(@confidences)
    }
  end

  def normalize(_ref), do: nil

  @spec normalize_many(term()) :: [t()]
  def normalize_many(refs) when is_list(refs) do
    refs
    |> Enum.map(&normalize/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_many(_refs), do: []
end
