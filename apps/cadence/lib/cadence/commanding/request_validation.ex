defmodule Cadence.Commanding.RequestValidation do
  @moduledoc """
  Resolves the active Mission Model command plan and validates request arguments.
  """

  alias Cadence.Activations

  alias Cadence.Catalog.Command.Compiler.{
    OperationalBinding,
    RuntimeDefinition
  }

  alias Cadence.Catalog.Command.Invocation
  alias Cadence.Commanding.CommandRequest
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Missions
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.SourceEndpoints

  @spec validate_and_enrich(CommandRequest.t()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def validate_and_enrich(%CommandRequest{} = command_request) do
    with {:ok, _mission} <-
           Missions.fetch_mission(command_request.organization_id, command_request.mission_id),
         {:ok, _source_endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             command_request.organization_id,
             command_request.mission_id,
             command_request.source_endpoint_ref
           ),
         {:ok, request_basis} <-
           resolve_basis(
             command_request.organization_id,
             command_request.mission_id,
             command_request.mission_model_revision_id,
             command_request.command_id
           ),
         {:ok, resolved_argument_values} <-
           Invocation.resolve(
             request_basis.runtime_definition,
             command_request.argument_values
           ) do
      {:ok,
       CommandRequest.new(%{
         command_request_id: command_request.command_request_id,
         organization_id: command_request.organization_id,
         mission_id: command_request.mission_id,
         source_endpoint_ref: command_request.source_endpoint_ref,
         mission_model_revision_id: command_request.mission_model_revision_id,
         command_id: command_request.command_id,
         command_name: request_basis.runtime_definition.name,
         command_display_name: request_basis.runtime_definition.display_name,
         lifecycle_state:
           request_lifecycle_state(
             request_basis.operational_binding.significance,
             request_basis.operational_binding.critical,
             request_basis.operational_binding.hazardous,
             request_basis.operational_binding.release_policy_hint
           ),
         priority: command_request.priority,
         not_before: command_request.not_before,
         expires_at: command_request.expires_at,
         requested_by: command_request.requested_by,
         source_command_stage_id: command_request.source_command_stage_id,
         source_staged_command_item_id: command_request.source_staged_command_item_id,
         argument_values: normalize_argument_values(command_request.argument_values),
         resolved_argument_values: resolved_argument_values,
         significance: request_basis.operational_binding.significance,
         critical: request_basis.operational_binding.critical,
         hazardous: request_basis.operational_binding.hazardous,
         subsystem: request_basis.operational_binding.subsystem,
         group_name: request_basis.operational_binding.group_name,
         preferred_uplink_service: request_basis.operational_binding.preferred_uplink_service,
         release_policy_hint: request_basis.operational_binding.release_policy_hint,
         apid: request_basis.operational_binding.apid,
         service_type: request_basis.operational_binding.service_type,
         service_subtype: request_basis.operational_binding.service_subtype,
         opcode: request_basis.operational_binding.opcode,
         requested_at: command_request.requested_at || DateTime.utc_now(),
         metadata:
           Map.merge(command_request.metadata, %{
             "validation_basis" => validation_basis(request_basis)
           })
       })}
    end
  end

  @spec resolve_basis(binary(), binary(), binary(), binary()) ::
          {:ok,
           %{
             runtime_definition: RuntimeDefinition.t(),
             constraint_plans: [Cadence.Catalog.Command.Compiler.ConstraintPlan.t()],
             verifier_plans: [Cadence.Catalog.Command.Compiler.VerifierPlan.t()],
             operational_binding: OperationalBinding.t(),
             mission_model_revision_id: binary(),
             runtime_plan_id: binary()
           }}
          | {:error, term()}
  def resolve_basis(organization_id, mission_id, mission_model_revision_id, command_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(mission_model_revision_id) and is_binary(command_id) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id),
         {:ok, %{runtime_plans: plans} = runtime_basis} <-
           MissionModelPromotion.runtime_basis(activation),
         :ok <- exact_revision(runtime_basis, mission_model_revision_id),
         {:ok, basis} <- MissionModelPlanDecoder.command_basis(plans, command_id) do
      {:ok,
       basis
       |> Map.put(:mission_model_revision_id, runtime_basis.mission_model_revision_id)
       |> Map.put(:runtime_plan_id, basis.plan_id)
       |> Map.delete(:plan_id)}
    end
  end

  defp exact_revision(%{mission_model_revision_id: revision_id}, revision_id), do: :ok

  defp exact_revision(%{mission_model_revision_id: active}, requested),
    do: {:error, {:mission_model_revision_mismatch, requested, active}}

  defp exact_revision(%{}, requested),
    do: {:error, {:mission_model_revision_not_active, requested}}

  defp validation_basis(request_basis) do
    %{
      "runtime_layout_id" => request_basis.runtime_definition.layout_id,
      "mission_model_revision_id" => request_basis.mission_model_revision_id,
      "runtime_plan_id" => request_basis.runtime_plan_id
    }
  end

  defp normalize_argument_values(argument_values) when is_map(argument_values) do
    Map.new(argument_values, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_argument_values(_other), do: %{}

  defp request_lifecycle_state(significance, critical, hazardous, release_policy_hint) do
    if approval_required?(significance, critical, hazardous, release_policy_hint) do
      :approval_pending
    else
      :validated
    end
  end

  defp approval_required?(significance, critical, hazardous, release_policy_hint) do
    critical or hazardous or significance in [:critical, :hazardous] or
      release_policy_hint in ["confirmation_required", "approval_required"]
  end
end
