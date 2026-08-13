defmodule Cadence.Commanding.RequestValidation do
  @moduledoc """
  Resolves catalog command definitions and validates command-request arguments.
  """

  alias Cadence.{Activations, Catalog}
  alias Cadence.Catalog.Command.Compiler

  alias Cadence.Catalog.Command.Compiler.{
    OperationalBinding,
    RuntimeDefinition
  }

  alias Cadence.Catalog.Command.Definition, as: CommandDefinition
  alias Cadence.Catalog.Command.Invocation
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
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
             command_request.command_snapshot_id,
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
         command_snapshot_id: command_request.command_snapshot_id,
         command_id: command_request.command_id,
         command_name: request_basis.definition.name,
         command_display_name: request_basis.definition.display_name,
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
             snapshot: CommandSnapshot.t(),
             definition: CommandDefinition.t(),
             runtime_definition: RuntimeDefinition.t(),
             constraint_plans: [Compiler.ConstraintPlan.t()],
             verifier_plans: [Compiler.VerifierPlan.t()],
             operational_binding: OperationalBinding.t(),
             mission_model_revision_id: binary() | nil,
             runtime_plan_id: binary() | nil
           }}
          | {:error, term()}
  def resolve_basis(organization_id, mission_id, command_snapshot_id, command_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_snapshot_id) and is_binary(command_id) do
    case active_mission_model_basis(
           organization_id,
           mission_id,
           command_snapshot_id,
           command_id
         ) do
      {:ok, basis} -> {:ok, basis}
      :legacy -> legacy_basis(organization_id, mission_id, command_snapshot_id, command_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp legacy_basis(organization_id, mission_id, command_snapshot_id, command_id) do
    with {:ok, %CommandSnapshot{} = snapshot} <-
           Catalog.fetch_command_snapshot(organization_id, mission_id, command_snapshot_id),
         {:ok, %CommandDefinition{} = definition} <-
           fetch_command_definition(snapshot, command_id),
         compiler_result <- Compiler.compile(snapshot),
         {:ok, %RuntimeDefinition{} = runtime_definition} <-
           fetch_runtime_definition(compiler_result, command_id),
         verifier_plans <- fetch_verifier_plans(compiler_result, command_id),
         {:ok, %OperationalBinding{} = operational_binding} <-
           fetch_operational_binding(compiler_result, command_id) do
      {:ok,
       %{
         snapshot: snapshot,
         definition: definition,
         runtime_definition: runtime_definition,
         constraint_plans: fetch_constraint_plans(compiler_result, command_id),
         verifier_plans: verifier_plans,
         operational_binding: operational_binding,
         mission_model_revision_id: nil,
         runtime_plan_id: nil
       }}
    end
  end

  defp active_mission_model_basis(organization_id, mission_id, command_snapshot_id, command_id) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id),
         {:ok, runtime_basis} <- MissionModelPromotion.runtime_basis(activation) do
      resolve_active_runtime_basis(
        organization_id,
        mission_id,
        command_snapshot_id,
        command_id,
        runtime_basis
      )
    else
      {:error, :no_active_binding_set} -> :legacy
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_active_runtime_basis(
         organization_id,
         mission_id,
         command_snapshot_id,
         command_id,
         %{runtime_plans: plans} = runtime_basis
       ) do
    with {:ok, basis} <-
           MissionModelPlanDecoder.command_basis(plans, command_snapshot_id, command_id) do
      {:ok, mission_model_basis(organization_id, mission_id, runtime_basis, basis)}
    end
  end

  defp resolve_active_runtime_basis(
         _organization_id,
         _mission_id,
         _command_snapshot_id,
         _command_id,
         %{}
       ),
       do: :legacy

  defp mission_model_basis(organization_id, mission_id, runtime_basis, basis) do
    basis
    |> Map.put(
      :snapshot,
      mission_model_snapshot(
        organization_id,
        mission_id,
        runtime_basis.mission_model_revision_id,
        basis
      )
    )
    |> Map.put(:mission_model_revision_id, runtime_basis.mission_model_revision_id)
    |> Map.put(:runtime_plan_id, basis.plan_id)
    |> Map.delete(:plan_id)
  end

  defp mission_model_snapshot(organization_id, mission_id, revision_id, basis) do
    CommandSnapshot.new(%{
      snapshot_id: basis.runtime_definition.snapshot_id,
      organization_id: organization_id,
      mission_id: mission_id,
      artifact_id: "mission_model:" <> revision_id,
      import_run_id: revision_id,
      importer_key: "mission_model_runtime_plan",
      snapshot_name: "Mission Model " <> revision_id,
      command_definitions: [basis.definition]
    })
  end

  defp fetch_command_definition(%CommandSnapshot{} = snapshot, command_id) do
    case Enum.find(snapshot.command_definitions, &(&1.command_id == command_id)) do
      nil -> {:error, {:command_definition_not_found, snapshot.snapshot_id, command_id}}
      %CommandDefinition{} = definition -> {:ok, definition}
    end
  end

  defp fetch_runtime_definition(compiler_result, command_id) do
    case Enum.find(compiler_result.runtime_definitions, &(&1.command_id == command_id)) do
      nil -> {:error, {:command_runtime_definition_not_found, command_id}}
      %RuntimeDefinition{} = runtime_definition -> {:ok, runtime_definition}
    end
  end

  defp fetch_operational_binding(compiler_result, command_id) do
    case Enum.find(compiler_result.operational_bindings, &(&1.command_id == command_id)) do
      nil -> {:error, {:command_operational_binding_not_found, command_id}}
      %OperationalBinding{} = operational_binding -> {:ok, operational_binding}
    end
  end

  defp fetch_verifier_plans(compiler_result, command_id) do
    Enum.filter(compiler_result.verifier_plans, &(&1.command_id == command_id))
  end

  defp fetch_constraint_plans(compiler_result, command_id) do
    Enum.filter(compiler_result.constraint_plans, &(&1.command_id == command_id))
  end

  defp validation_basis(request_basis) do
    %{
      "snapshot_id" => request_basis.snapshot.snapshot_id,
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
