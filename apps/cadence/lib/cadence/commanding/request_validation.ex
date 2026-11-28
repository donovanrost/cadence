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
  def validate_on_snapshot(%CommandRequest{} = request, snapshot, expected_target \\ nil) do
    context = prepare([request], snapshot)
    {result, _context} = validate_prepared(request, context, expected_target)
    result
  end

  @doc """
  Reads, once, what validating `requests` against `snapshot` needs (#1041): every distinct target
  (one `FOR SHARE` read, in endpoint order), the targets' fleet entries (one read), and each
  distinct model's basis and decoded catalog (once per model, not per target). Returns a context
  for `validate_prepared/3`, which also remembers what it decodes (a command's plan, the values
  an argument set resolves to, an enumerated argument's choices), so a group of thousands of
  members costs a fixed number of reads. Must run inside a transaction, like
  `validate_on_snapshot/3`.
  """
  def prepare([], snapshot), do: %{snapshot: snapshot, targets: %{}, bases: %{}, memo: %{}}

  def prepare([%CommandRequest{} = first | _] = requests, snapshot) do
    targets =
      SourceEndpoints.fetch_command_authoring_targets(
        first.organization_id,
        first.mission_id,
        Enum.map(requests, & &1.source_endpoint_ref)
      )

    found = for {_id, {:ok, target}} <- targets, do: target

    %{
      snapshot: snapshot,
      targets: targets,
      bases: ActiveBasis.for_targets(snapshot, found),
      memo: %{}
    }
  end

  @doc """
  `validate_on_snapshot/3` for a request `prepare/2` was given: `{result, context}`, the result
  exactly what `validate_on_snapshot/3` returns, the context carrying what this request decoded
  for the next.
  """
  def validate_prepared(%CommandRequest{} = request, context, expected_target \\ nil) do
    with {:ok, target} <- Map.fetch!(context.targets, request.source_endpoint_ref),
         target_token = authoring_digest(target),
         true <- is_nil(expected_target) or target_token == expected_target,
         {:ok, snapshot} <- Map.fetch!(context.bases, target.source_endpoint_id) do
      resolve(request, %{target: target, target_token: target_token, snapshot: snapshot}, context)
    else
      false -> {{:error, :command_authoring_basis_changed}, context}
      {:error, reason} -> {{:error, reason}, context}
    end
  end

  defp resolve(request, %{snapshot: snapshot} = state, context) do
    revision = snapshot.basis.mission_model_revision_id
    key = {:command_basis, revision, request.command_id}

    {command_basis, context} =
      remember(context, key, fn ->
        MissionModelPlanDecoder.command_basis(snapshot.basis.runtime_plans, request.command_id)
      end)

    with {:ok, basis} <- command_basis,
         true <- request.mission_model_revision_id in [nil, revision] do
      request = %{request | mission_model_revision_id: revision}

      basis =
        basis
        |> Map.put(:mission_model_revision_id, revision)
        |> Map.put(:runtime_plan_id, basis.plan_id)

      resolve_values(request, basis, state, context)
    else
      false -> {{:error, :command_authoring_basis_changed}, context}
      {:error, reason} -> {{:error, reason}, context}
    end
  end

  # The values an argument set resolves to, and whether they encode, depend only on the model's
  # definition and the arguments: the same for every target that sends them.
  defp resolve_values(request, basis, state, context) do
    definition = basis.runtime_definition

    values_key =
      {:values, definition.mission_model_revision_id, request.command_id, request.argument_values}

    {values, context} =
      remember(context, values_key, fn ->
        with {:ok, values} <- Invocation.resolve(definition, request.argument_values),
             :ok <- WireEncoding.validate(definition, values) do
          {:ok, values}
        end
      end)

    with {:ok, values} <- values,
         {:ok, context} <- validate_choices(request, definition, values, context) do
      {{:ok, enrich(request, basis, values), state}, context}
    else
      {:error, reason} -> {{:error, reason}, context}
      {:error, reason, context} -> {{:error, reason}, context}
    end
  end

  defp remember(%{memo: memo} = context, key, compute) do
    case Map.fetch(memo, key) do
      {:ok, result} ->
        {result, context}

      :error ->
        result = compute.()
        {result, %{context | memo: Map.put(memo, key, result)}}
    end
  end

  @doc false
  defdelegate authoring_digest(value), to: Cadence.Commanding.AuthoringIdentity, as: :digest

  # One read of an enumerated argument's choices per model and argument set.
  defp validate_choices(request, definition, values, context) do
    specs = Enum.filter(definition.argument_specs, &(&1.base_type == :enumerated))
    ids = Enum.map(specs, & &1.argument_id)
    key = {:choices, definition.mission_model_revision_id, ids}

    {choices, context} =
      remember(context, key, fn ->
        MissionModels.command_argument_choices(
          request.organization_id,
          request.mission_id,
          definition.mission_model_revision_id,
          ids
        )
      end)

    with {:ok, choices} <- choices,
         :ok <-
           Enum.reduce_while(specs, :ok, fn spec, :ok ->
             validate_choice(spec, values, choices)
           end) do
      {:ok, context}
    else
      {:error, reason} -> {:error, reason, context}
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
    organization_id
    |> resolve_bases(mission_id, mission_model_revision_id, [command_id], source_endpoint_id)
    |> Map.fetch!(command_id)
  end

  @doc """
  `resolve_basis/5` for several commands of one revision and endpoint: the active basis (the
  activation, the revision and its plans) is read once, and each command is decoded from it.
  `%{command_id => result}`, each result what `resolve_basis/5` returns for that command.
  """
  @spec resolve_bases(binary(), binary(), binary(), [binary()], binary() | nil) :: %{
          binary() => {:ok, map()} | {:error, term()}
        }
  def resolve_bases(organization_id, mission_id, revision_id, command_ids, source_endpoint_id) do
    with {:ok, %{runtime_plans: plans} = runtime_basis} <-
           ActiveBasis.fetch_command_runtime_basis(
             organization_id,
             mission_id,
             source_endpoint_id
           ),
         :ok <- exact_revision(runtime_basis, revision_id, organization_id, mission_id) do
      Map.new(command_ids, fn command_id ->
        {command_id, command_resolved(plans, command_id, runtime_basis)}
      end)
    else
      {:error, _reason} = error -> Map.new(command_ids, &{&1, error})
    end
  end

  defp command_resolved(plans, command_id, runtime_basis) do
    with {:ok, basis} <- MissionModelPlanDecoder.command_basis(plans, command_id) do
      {:ok,
       basis
       |> Map.put(:mission_model_revision_id, runtime_basis.mission_model_revision_id)
       |> Map.put(:runtime_plan_id, basis.plan_id)
       |> Map.delete(:plan_id)}
    end
  end

  @doc """
  The basis of each distinct (pinned revision, command) among `requests`: `%{{revision, command}
  => result}`, with one read of the active basis per distinct (revision, endpoint of the first
  request carrying it) instead of one per command.
  """
  @spec resolve_keyed(binary(), binary(), [map()]) :: %{{binary(), binary()} => term()}
  def resolve_keyed(organization_id, mission_id, requests) do
    requests
    |> Enum.uniq_by(&{&1.mission_model_revision_id, &1.command_id})
    |> Enum.group_by(&{&1.mission_model_revision_id, &1.source_endpoint_ref})
    |> Enum.reduce(%{}, fn {{revision, endpoint}, same}, acc ->
      commands = Enum.map(same, & &1.command_id)

      organization_id
      |> resolve_bases(mission_id, revision, commands, endpoint)
      |> Enum.reduce(acc, fn {command, result}, acc ->
        Map.put(acc, {revision, command}, result)
      end)
    end)
  end

  # The revision a request was validated on is still the one its craft runs, or (#1107) another
  # revision with the very same command plan: a monitoring apply moves craft to a new head
  # revision, and what a command encodes and verifies against, its command plan, is unchanged, so a
  # request already queued can still release.
  defp exact_revision(%{mission_model_revision_id: revision_id}, revision_id, _org, _mission),
    do: :ok

  defp exact_revision(
         %{mission_model_revision_id: active} = runtime_basis,
         requested,
         org,
         mission
       ) do
    if same_command_plan?(runtime_basis, org, mission, requested),
      do: :ok,
      else: {:error, {:mission_model_revision_mismatch, requested, active}}
  end

  defp exact_revision(%{}, requested, _org, _mission),
    do: {:error, {:mission_model_revision_not_active, requested}}

  defp same_command_plan?(%{runtime_plans: %{command: active}}, org, mission, requested) do
    case MissionModels.fetch_plan(org, mission, requested, :command) do
      {:ok, plan} ->
        {plan.plan_id, plan.content_sha256, plan.target_contract_version} ==
          {active.plan_id, active.content_sha256, active.target_contract_version}

      {:error, _reason} ->
        false
    end
  end

  defp same_command_plan?(_runtime_basis, _org, _mission, _requested), do: false

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
