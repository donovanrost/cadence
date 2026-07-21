defmodule Cadence.Commanding.RequestValidation do
  @moduledoc """
  Resolves catalog command definitions and validates command-request arguments.
  """

  alias Cadence.Catalog
  alias Cadence.Catalog.Command.Compiler

  alias Cadence.Catalog.Command.Compiler.{
    OperationalBinding,
    RuntimeDefinition
  }

  alias Cadence.Catalog.Command.Definition, as: CommandDefinition
  alias Cadence.Catalog.Command.Invocation
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Commanding.CommandRequest
  alias Cadence.Missions
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
             "validation_basis" => %{
               "snapshot_id" => request_basis.snapshot.snapshot_id,
               "runtime_layout_id" => request_basis.runtime_definition.layout_id
             }
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
             verifier_plans: [Compiler.VerifierPlan.t()],
             operational_binding: OperationalBinding.t()
           }}
          | {:error, term()}
  def resolve_basis(organization_id, mission_id, command_snapshot_id, command_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_snapshot_id) and is_binary(command_id) do
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
         verifier_plans: verifier_plans,
         operational_binding: operational_binding
       }}
    end
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
