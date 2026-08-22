defmodule Cadence.Management.Commanding.ApprovedCommand do
  @moduledoc """
  Immutable management-to-control handoff for an approved command intent.

  The content hash excludes operational lifecycle and verification state so
  Control can prove that the queued request still has the approved command
  basis even after its lifecycle advances from approved to queued.
  """

  alias Cadence.Commanding.{CommandApproval, CommandRequest}
  alias Cadence.Platform.ContentHash

  @type t :: %__MODULE__{
          content_sha256: binary(),
          command_approval_id: binary(),
          command_request_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          source_endpoint_ref: binary(),
          mission_model_revision_id: binary(),
          command_id: binary(),
          command_name: binary() | nil,
          command_display_name: binary() | nil,
          priority: non_neg_integer(),
          not_before: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          requested_by: map(),
          resolved_argument_values: map(),
          significance: atom() | nil,
          critical: boolean(),
          hazardous: boolean(),
          subsystem: binary() | nil,
          group_name: binary() | nil,
          preferred_uplink_service: binary() | nil,
          release_policy_hint: binary() | nil,
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term(),
          requested_at: DateTime.t() | nil,
          approved_by: map(),
          approved_at: DateTime.t(),
          metadata: map()
        }

  @enforce_keys [
    :content_sha256,
    :command_approval_id,
    :command_request_id,
    :organization_id,
    :mission_id,
    :source_endpoint_ref,
    :mission_model_revision_id,
    :command_id,
    :priority,
    :requested_by,
    :resolved_argument_values,
    :critical,
    :hazardous,
    :approved_by,
    :approved_at,
    :metadata
  ]
  defstruct @enforce_keys ++
              [
                :command_name,
                :command_display_name,
                :not_before,
                :expires_at,
                :significance,
                :subsystem,
                :group_name,
                :preferred_uplink_service,
                :release_policy_hint,
                :apid,
                :service_type,
                :service_subtype,
                :opcode,
                :requested_at
              ]

  @spec new(CommandRequest.t(), CommandApproval.t()) :: {:ok, t()} | {:error, term()}
  def new(
        %CommandRequest{lifecycle_state: :approved} = request,
        %CommandApproval{decision: :approved} = approval
      ) do
    with true <- request.organization_id == approval.organization_id,
         true <- request.mission_id == approval.mission_id,
         true <- request.command_request_id == approval.command_request_id,
         %DateTime{} = approved_at <- approval.decided_at do
      basis = basis(request)

      {:ok,
       struct!(
         __MODULE__,
         basis
         |> Map.merge(%{
           content_sha256: ContentHash.term_sha256(basis),
           command_approval_id: approval.command_approval_id,
           approved_by: approval.decided_by,
           approved_at: approved_at
         })
       )}
    else
      false -> {:error, :approved_command_identity_mismatch}
      nil -> {:error, :approved_command_missing_approval_time}
      _other -> {:error, :approved_command_missing_approval_time}
    end
  end

  def new(%CommandRequest{}, %CommandApproval{}), do: {:error, :command_not_approved}

  @spec from_automatic_policy(CommandRequest.t()) :: {:ok, t()} | {:error, term()}
  def from_automatic_policy(%CommandRequest{lifecycle_state: state} = request)
      when state in [:validated, :approved] do
    approved_at = request.requested_at || DateTime.utc_now()

    approval =
      CommandApproval.new(%{
        command_approval_id: "policy:auto:#{request.command_request_id}",
        organization_id: request.organization_id,
        mission_id: request.mission_id,
        command_request_id: request.command_request_id,
        decision: :approved,
        decided_by: %{
          "kind" => "service",
          "id" => "cadence:command_safety_policy",
          "display_name" => "Cadence Command Safety Policy"
        },
        decided_at: approved_at,
        reason: "Approval not required by command safety policy"
      })

    new(%{request | lifecycle_state: :approved}, approval)
  end

  def from_automatic_policy(%CommandRequest{}), do: {:error, :command_not_approved}

  @spec matches_request?(t(), CommandRequest.t()) :: boolean()
  def matches_request?(%__MODULE__{} = approved_command, %CommandRequest{} = request) do
    ContentHash.term_sha256(basis(request)) == approved_command.content_sha256
  end

  defp basis(%CommandRequest{} = request) do
    %{
      command_request_id: request.command_request_id,
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      source_endpoint_ref: request.source_endpoint_ref,
      mission_model_revision_id: request.mission_model_revision_id,
      command_id: request.command_id,
      command_name: request.command_name,
      command_display_name: request.command_display_name,
      priority: request.priority,
      not_before: request.not_before,
      expires_at: request.expires_at,
      requested_by: request.requested_by,
      resolved_argument_values: request.resolved_argument_values,
      significance: request.significance,
      critical: request.critical,
      hazardous: request.hazardous,
      subsystem: request.subsystem,
      group_name: request.group_name,
      preferred_uplink_service: request.preferred_uplink_service,
      release_policy_hint: request.release_policy_hint,
      apid: request.apid,
      service_type: request.service_type,
      service_subtype: request.service_subtype,
      opcode: request.opcode,
      requested_at: request.requested_at,
      metadata: request.metadata
    }
  end
end
