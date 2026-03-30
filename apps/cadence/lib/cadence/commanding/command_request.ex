defmodule Cadence.Commanding.CommandRequest do
  @moduledoc """
  Durable formal command intent record created from staged items or direct
  commanding flows.
  """

  alias Cadence.Ids

  @type lifecycle_state ::
          :draft
          | :validated
          | :approval_pending
          | :approved
          | :rejected
          | :queued
          | :released
          | :canceled

  @type significance :: :routine | :warning | :critical | :hazardous | nil
  @type verification_state :: :not_required | :pending | :satisfied | :failed | :timed_out | nil

  @type t :: %__MODULE__{
          command_request_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          source_endpoint_ref: binary(),
          command_snapshot_id: binary(),
          command_id: binary(),
          command_name: binary() | nil,
          command_display_name: binary() | nil,
          lifecycle_state: lifecycle_state(),
          verification_state: verification_state(),
          priority: non_neg_integer(),
          not_before: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          requested_by: map(),
          source_command_stage_id: binary() | nil,
          source_staged_command_item_id: binary() | nil,
          argument_values: map(),
          resolved_argument_values: map(),
          significance: significance(),
          critical: boolean(),
          hazardous: boolean(),
          subsystem: binary() | nil,
          group_name: binary() | nil,
          preferred_uplink_service: binary() | nil,
          release_policy_hint: binary() | nil,
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term() | nil,
          requested_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :command_request_id,
    :organization_id,
    :mission_id,
    :source_endpoint_ref,
    :command_snapshot_id,
    :command_id,
    :command_name,
    :command_display_name,
    :not_before,
    :expires_at,
    :verification_state,
    :source_command_stage_id,
    :source_staged_command_item_id,
    :significance,
    :subsystem,
    :group_name,
    :preferred_uplink_service,
    :release_policy_hint,
    :apid,
    :service_type,
    :service_subtype,
    :opcode,
    :requested_at,
    requested_by: %{},
    lifecycle_state: :draft,
    priority: 3,
    argument_values: %{},
    resolved_argument_values: %{},
    critical: false,
    hazardous: false,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_request_id:
        Map.get(
          attrs,
          :command_request_id,
          Map.get(attrs, "command_request_id", Ids.new("command_request"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      source_endpoint_ref: Map.fetch!(attrs, :source_endpoint_ref),
      command_snapshot_id: Map.fetch!(attrs, :command_snapshot_id),
      command_id: Map.fetch!(attrs, :command_id),
      command_name: Map.get(attrs, :command_name, Map.get(attrs, "command_name")),
      command_display_name:
        Map.get(attrs, :command_display_name, Map.get(attrs, "command_display_name")),
      lifecycle_state:
        normalize_lifecycle_state(
          Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :draft))
        ),
      verification_state:
        normalize_verification_state(
          Map.get(attrs, :verification_state, Map.get(attrs, "verification_state"))
        ),
      priority: Map.get(attrs, :priority, Map.get(attrs, "priority", 3)),
      not_before: Map.get(attrs, :not_before, Map.get(attrs, "not_before")),
      expires_at: Map.get(attrs, :expires_at, Map.get(attrs, "expires_at")),
      requested_by: Map.get(attrs, :requested_by, Map.get(attrs, "requested_by", %{})),
      source_command_stage_id:
        Map.get(attrs, :source_command_stage_id, Map.get(attrs, "source_command_stage_id")),
      source_staged_command_item_id:
        Map.get(
          attrs,
          :source_staged_command_item_id,
          Map.get(attrs, "source_staged_command_item_id")
        ),
      argument_values: Map.get(attrs, :argument_values, Map.get(attrs, "argument_values", %{})),
      resolved_argument_values:
        Map.get(attrs, :resolved_argument_values, Map.get(attrs, "resolved_argument_values", %{})),
      significance:
        normalize_significance(Map.get(attrs, :significance, Map.get(attrs, "significance"))),
      critical: Map.get(attrs, :critical, Map.get(attrs, "critical", false)),
      hazardous: Map.get(attrs, :hazardous, Map.get(attrs, "hazardous", false)),
      subsystem: Map.get(attrs, :subsystem, Map.get(attrs, "subsystem")),
      group_name: Map.get(attrs, :group_name, Map.get(attrs, "group_name")),
      preferred_uplink_service:
        Map.get(attrs, :preferred_uplink_service, Map.get(attrs, "preferred_uplink_service")),
      release_policy_hint:
        Map.get(attrs, :release_policy_hint, Map.get(attrs, "release_policy_hint")),
      apid: Map.get(attrs, :apid, Map.get(attrs, "apid")),
      service_type: Map.get(attrs, :service_type, Map.get(attrs, "service_type")),
      service_subtype: Map.get(attrs, :service_subtype, Map.get(attrs, "service_subtype")),
      opcode: Map.get(attrs, :opcode, Map.get(attrs, "opcode")),
      requested_at: Map.get(attrs, :requested_at, Map.get(attrs, "requested_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_lifecycle_state(:draft), do: :draft
  defp normalize_lifecycle_state("draft"), do: :draft
  defp normalize_lifecycle_state(:validated), do: :validated
  defp normalize_lifecycle_state("validated"), do: :validated
  defp normalize_lifecycle_state(:approval_pending), do: :approval_pending
  defp normalize_lifecycle_state("approval_pending"), do: :approval_pending
  defp normalize_lifecycle_state(:approved), do: :approved
  defp normalize_lifecycle_state("approved"), do: :approved
  defp normalize_lifecycle_state(:rejected), do: :rejected
  defp normalize_lifecycle_state("rejected"), do: :rejected
  defp normalize_lifecycle_state(:queued), do: :queued
  defp normalize_lifecycle_state("queued"), do: :queued
  defp normalize_lifecycle_state(:released), do: :released
  defp normalize_lifecycle_state("released"), do: :released
  defp normalize_lifecycle_state(:canceled), do: :canceled
  defp normalize_lifecycle_state("canceled"), do: :canceled
  defp normalize_lifecycle_state(_other), do: :draft

  defp normalize_verification_state(nil), do: nil
  defp normalize_verification_state(:not_required), do: :not_required
  defp normalize_verification_state("not_required"), do: :not_required
  defp normalize_verification_state(:pending), do: :pending
  defp normalize_verification_state("pending"), do: :pending
  defp normalize_verification_state(:satisfied), do: :satisfied
  defp normalize_verification_state("satisfied"), do: :satisfied
  defp normalize_verification_state(:failed), do: :failed
  defp normalize_verification_state("failed"), do: :failed
  defp normalize_verification_state(:timed_out), do: :timed_out
  defp normalize_verification_state("timed_out"), do: :timed_out
  defp normalize_verification_state(_other), do: nil

  defp normalize_significance(nil), do: nil
  defp normalize_significance(:routine), do: :routine
  defp normalize_significance("routine"), do: :routine
  defp normalize_significance(:warning), do: :warning
  defp normalize_significance("warning"), do: :warning
  defp normalize_significance(:critical), do: :critical
  defp normalize_significance("critical"), do: :critical
  defp normalize_significance(:hazardous), do: :hazardous
  defp normalize_significance("hazardous"), do: :hazardous
  defp normalize_significance(_other), do: nil
end
