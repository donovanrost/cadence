defmodule Cadence.Commanding.CommandVerifierInstance do
  @moduledoc """
  Durable post-release verifier instance created from a compiled verifier plan.
  """

  alias Cadence.Catalog.Command.Compiler.VerifierPlan
  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Ids

  @type lifecycle_state :: :pending | :satisfied | :failed | :timed_out | :canceled
  @type phase :: VerifierPlan.phase()
  @type severity :: VerifierPlan.severity()

  @type t :: %__MODULE__{
          command_verifier_instance_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          command_request_id: binary(),
          command_release_attempt_id: binary(),
          source_endpoint_ref: binary(),
          command_snapshot_id: binary(),
          command_id: binary(),
          command_name: binary() | nil,
          verifier_id: binary(),
          verifier_name: binary(),
          phase: phase(),
          severity: severity(),
          success_criteria: MatchCriteria.t() | nil,
          failure_criteria: MatchCriteria.t() | nil,
          delay_until: DateTime.t() | nil,
          timeout_at: DateTime.t() | nil,
          lifecycle_state: lifecycle_state(),
          matched_record_kind:
            :telemetry_sample | :transport_action_request | :transport_capability_record | nil,
          matched_record_id: binary() | nil,
          matched_at: DateTime.t() | nil,
          failure_reason: binary() | nil,
          metadata: map()
        }

  defstruct [
    :command_verifier_instance_id,
    :organization_id,
    :mission_id,
    :command_request_id,
    :command_release_attempt_id,
    :source_endpoint_ref,
    :command_snapshot_id,
    :command_id,
    :command_name,
    :verifier_id,
    :verifier_name,
    :phase,
    :severity,
    :success_criteria,
    :failure_criteria,
    :delay_until,
    :timeout_at,
    :matched_record_kind,
    :matched_record_id,
    :matched_at,
    :failure_reason,
    lifecycle_state: :pending,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_verifier_instance_id:
        Map.get(
          attrs,
          :command_verifier_instance_id,
          Map.get(attrs, "command_verifier_instance_id", Ids.new("command_verifier_instance"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      command_request_id: Map.fetch!(attrs, :command_request_id),
      command_release_attempt_id: Map.fetch!(attrs, :command_release_attempt_id),
      source_endpoint_ref: Map.fetch!(attrs, :source_endpoint_ref),
      command_snapshot_id: Map.fetch!(attrs, :command_snapshot_id),
      command_id: Map.fetch!(attrs, :command_id),
      command_name: Map.get(attrs, :command_name, Map.get(attrs, "command_name")),
      verifier_id: Map.fetch!(attrs, :verifier_id),
      verifier_name: Map.fetch!(attrs, :verifier_name),
      phase: normalize_phase(Map.get(attrs, :phase, Map.get(attrs, "phase", :completion))),
      severity: normalize_severity(Map.get(attrs, :severity, Map.get(attrs, "severity"))),
      success_criteria: Map.get(attrs, :success_criteria, Map.get(attrs, "success_criteria")),
      failure_criteria: Map.get(attrs, :failure_criteria, Map.get(attrs, "failure_criteria")),
      delay_until: Map.get(attrs, :delay_until, Map.get(attrs, "delay_until")),
      timeout_at: Map.get(attrs, :timeout_at, Map.get(attrs, "timeout_at")),
      lifecycle_state:
        normalize_lifecycle_state(
          Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :pending))
        ),
      matched_record_kind:
        normalize_matched_record_kind(
          Map.get(attrs, :matched_record_kind, Map.get(attrs, "matched_record_kind"))
        ),
      matched_record_id: Map.get(attrs, :matched_record_id, Map.get(attrs, "matched_record_id")),
      matched_at: Map.get(attrs, :matched_at, Map.get(attrs, "matched_at")),
      failure_reason: Map.get(attrs, :failure_reason, Map.get(attrs, "failure_reason")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_lifecycle_state(:pending), do: :pending
  defp normalize_lifecycle_state("pending"), do: :pending
  defp normalize_lifecycle_state(:satisfied), do: :satisfied
  defp normalize_lifecycle_state("satisfied"), do: :satisfied
  defp normalize_lifecycle_state(:failed), do: :failed
  defp normalize_lifecycle_state("failed"), do: :failed
  defp normalize_lifecycle_state(:timed_out), do: :timed_out
  defp normalize_lifecycle_state("timed_out"), do: :timed_out
  defp normalize_lifecycle_state(:canceled), do: :canceled
  defp normalize_lifecycle_state("canceled"), do: :canceled
  defp normalize_lifecycle_state(_other), do: :pending

  defp normalize_phase(:acceptance), do: :acceptance
  defp normalize_phase("acceptance"), do: :acceptance
  defp normalize_phase(:start), do: :start
  defp normalize_phase("start"), do: :start
  defp normalize_phase(:completion), do: :completion
  defp normalize_phase("completion"), do: :completion
  defp normalize_phase(:custom), do: :custom
  defp normalize_phase("custom"), do: :custom
  defp normalize_phase(_other), do: :completion

  defp normalize_severity(nil), do: nil
  defp normalize_severity(:info), do: :info
  defp normalize_severity("info"), do: :info
  defp normalize_severity(:warning), do: :warning
  defp normalize_severity("warning"), do: :warning
  defp normalize_severity(:error), do: :error
  defp normalize_severity("error"), do: :error
  defp normalize_severity(:critical), do: :critical
  defp normalize_severity("critical"), do: :critical
  defp normalize_severity(_other), do: nil

  defp normalize_matched_record_kind(nil), do: nil
  defp normalize_matched_record_kind(:telemetry_sample), do: :telemetry_sample
  defp normalize_matched_record_kind("telemetry_sample"), do: :telemetry_sample
  defp normalize_matched_record_kind(:transport_action_request), do: :transport_action_request
  defp normalize_matched_record_kind("transport_action_request"), do: :transport_action_request

  defp normalize_matched_record_kind(:transport_capability_record),
    do: :transport_capability_record

  defp normalize_matched_record_kind("transport_capability_record"),
    do: :transport_capability_record

  defp normalize_matched_record_kind(_other), do: nil
end
