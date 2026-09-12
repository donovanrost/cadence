defmodule Cadence.Commanding.RequestValidation do
  @moduledoc """
  Resolves the active Mission Model command plan and validates request arguments.
  """

  alias Cadence.Catalog.Command.Compiler.{
    OperationalBinding,
    RuntimeDefinition
  }

  alias Cadence.Catalog.Command.{Invocation, WireEncoding}
  alias Cadence.Commanding.CommandRequest
  alias Cadence.Missions
  alias Cadence.Reads.MissionModels.ActiveBasis
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
           ),
         :ok <- WireEncoding.validate(request_basis.runtime_definition, resolved_argument_values) do
      {:ok, enrich(command_request, request_basis, resolved_argument_values)}
    end
  end

  @doc "Runs an authoring snapshot against one locked active generation and bounded command plan."
  defdelegate with_authoring_catalog(organization_id, mission_id, operation),
    to: Cadence.Reads.MissionModels.ActiveBasis,
    as: :with_command_catalog

  @doc "Re-resolves a reviewed request while the model and target remain locked through the operation."
  def with_authoring_request(
        %CommandRequest{} = request,
        expected_basis,
        expected_target,
        operation
      ) do
    with_authoring_catalog(request.organization_id, request.mission_id, fn snapshot ->
      with true <- snapshot.token == expected_basis,
           {:ok, enriched, state} <- resolve_authoring_request(request, snapshot, expected_target) do
        operation.(enriched, state)
      else
        false -> {:error, :command_authoring_basis_changed}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc "Validates a finite batch under one admitted model and held target identities."
  def with_authoring_requests(
        [%CommandRequest{} = first | _] = requests,
        expected_basis,
        targets,
        operation
      )
      when length(requests) <= 25 and is_map(targets) do
    if same_scope?(requests, first) do
      resolve_authoring_batch(first, requests, expected_basis, targets, operation)
    else
      {:error, :invalid_command_authoring_batch}
    end
  end

  def with_authoring_requests(_, _, _, _), do: {:error, :invalid_command_authoring_batch}

  defp resolve_authoring_batch(first, requests, expected_basis, targets, operation) do
    with_authoring_catalog(first.organization_id, first.mission_id, fn snapshot ->
      with true <- expected_basis == :current or snapshot.token == expected_basis,
           {:ok, validated} <- resolve_authoring_requests(requests, snapshot, targets) do
        operation.(validated, snapshot)
      else
        false -> {:error, :command_authoring_basis_changed}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp same_scope?(requests, first) do
    Enum.all?(requests, fn
      %CommandRequest{organization_id: org, mission_id: mission} ->
        org == first.organization_id and mission == first.mission_id

      _ ->
        false
    end) and length(Enum.uniq_by(requests, & &1.command_request_id)) == length(requests)
  end

  defp resolve_authoring_requests(requests, snapshot, targets) do
    requests
    |> Enum.reduce_while({:ok, []}, fn request, {:ok, acc} ->
      case resolve_authoring_request(
             request,
             snapshot,
             Map.get(targets, request.command_request_id)
           ) do
        {:ok, enriched, state} ->
          {:cont, {:ok, [{enriched, state} | acc]}}

        {:error, reason} ->
          {:halt,
           {:error, {:command_authoring_request_failed, request.command_request_id, reason}}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp resolve_authoring_request(request, snapshot, expected_target) do
    with {:ok, target} <-
           SourceEndpoints.fetch_command_authoring_target(
             request.organization_id,
             request.mission_id,
             request.source_endpoint_ref
           ),
         target_token = authoring_digest(target),
         true <- is_nil(expected_target) or target_token == expected_target,
         {:ok, basis} <-
           MissionModelPlanDecoder.command_basis(snapshot.basis.runtime_plans, request.command_id),
         revision = snapshot.basis.mission_model_revision_id,
         true <- request.mission_model_revision_id in [nil, revision],
         request = %{request | mission_model_revision_id: revision},
         basis =
           basis
           |> Map.put(:mission_model_revision_id, revision)
           |> Map.put(:runtime_plan_id, basis.plan_id),
         {:ok, values} <- Invocation.resolve(basis.runtime_definition, request.argument_values),
         :ok <- WireEncoding.validate(basis.runtime_definition, values) do
      {:ok, enrich(request, basis, values),
       %{target: target, target_token: target_token, snapshot: snapshot}}
    else
      false -> {:error, :command_authoring_basis_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  defdelegate authoring_digest(value), to: Cadence.Commanding.AuthoringIdentity, as: :digest

  defp enrich(command_request, request_basis, resolved_argument_values) do
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
    })
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
    with {:ok, %{runtime_plans: plans} = runtime_basis} <-
           ActiveBasis.fetch_runtime_basis(organization_id, mission_id),
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
