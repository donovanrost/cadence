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
  alias Cadence.MissionModels
  alias Cadence.Reads.MissionModels.ActiveBasis
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.SourceEndpoints

  @doc "Runs an authoring snapshot against one locked active generation and bounded command plan."
  defdelegate with_authoring_catalog(organization_id, mission_id, operation),
    to: Cadence.Reads.MissionModels.ActiveBasis,
    as: :with_command_catalog

  @doc "The active command-catalog snapshot, read without the activation lock."
  defdelegate authoring_snapshot(organization_id, mission_id),
    to: Cadence.Reads.MissionModels.ActiveBasis,
    as: :command_catalog_snapshot

  @doc """
  Validates one request against a snapshot (from `authoring_snapshot/2` or
  `with_authoring_catalog/3`) with the exact authoring rules. Must run inside a
  transaction: target identities are read `FOR SHARE`. Returns the enriched
  request and `%{target, target_token, snapshot}`.
  """
  def validate_on_snapshot(%CommandRequest{} = request, snapshot, expected_target \\ nil),
    do: resolve_authoring_request(request, snapshot, expected_target)

  defp resolve_authoring_request(request, snapshot, expected_target) do
    with {:ok, target} <-
           SourceEndpoints.fetch_command_authoring_target(
             request.organization_id,
             request.mission_id,
             request.source_endpoint_ref
           ),
         target_token = authoring_digest(target),
         true <- is_nil(expected_target) or target_token == expected_target,
         {:ok, snapshot} <- ActiveBasis.for_target(snapshot, target),
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
         :ok <- WireEncoding.validate(basis.runtime_definition, values),
         :ok <- validate_choices(request, basis.runtime_definition, values) do
      {:ok, enrich(request, basis, values),
       %{target: target, target_token: target_token, snapshot: snapshot}}
    else
      false -> {:error, :command_authoring_basis_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  defdelegate authoring_digest(value), to: Cadence.Commanding.AuthoringIdentity, as: :digest

  defp validate_choices(request, definition, values) do
    specs = Enum.filter(definition.argument_specs, &(&1.base_type == :enumerated))

    with {:ok, choices} <-
           MissionModels.command_argument_choices(
             request.organization_id,
             request.mission_id,
             definition.mission_model_revision_id,
             Enum.map(specs, & &1.argument_id)
           ) do
      Enum.reduce_while(specs, :ok, fn spec, :ok ->
        validate_choice(spec, values, choices)
      end)
    end
  end

  defp validate_choice(spec, values, choices) do
    case Map.fetch(values, spec.name) do
      :error ->
        {:cont, :ok}

      {:ok, value} ->
        if Enum.any?(Map.fetch!(choices, spec.argument_id), &same_choice?(&1.value, value)),
          do: {:cont, :ok},
          else: {:halt, {:error, {:invalid_command_argument_choice, spec.name}}}
    end
  end

  defp same_choice?(expected, value) when is_integer(value), do: expected == value

  defp same_choice?(expected, value) when is_binary(value),
    do: Integer.parse(value) == {expected, ""}

  defp same_choice?(_, _), do: false

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
    resolve_basis(organization_id, mission_id, mission_model_revision_id, command_id, nil)
  end

  def resolve_basis(
        organization_id,
        mission_id,
        mission_model_revision_id,
        command_id,
        source_endpoint_id
      ) do
    with {:ok, %{runtime_plans: plans} = runtime_basis} <-
           ActiveBasis.fetch_command_runtime_basis(
             organization_id,
             mission_id,
             source_endpoint_id
           ),
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

  @doc """
  Whether a request for a command with this binding needs a second operator's
  approval (DECISIONS #7: critical or hazardous commands, or a policy hint).
  """
  @spec approval_required?(atom() | nil, boolean(), boolean(), binary() | nil) :: boolean()
  def approval_required?(significance, critical, hazardous, release_policy_hint) do
    critical or hazardous or significance in [:critical, :hazardous] or
      release_policy_hint in ["confirmation_required", "approval_required"]
  end
end
