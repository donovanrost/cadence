defmodule Cadence.Reads.CommandCatalog do
  @moduledoc """
  The command catalog of a mission's active generation, for the console (M17).

  `list/3` returns lightweight entries (identity, subsystem, hazard flags,
  whether a second operator's GO is required), filtered by `q` and paged by
  command id. `fetch/3` returns one command with its arguments (type, choices,
  default, fixed and hazardous values, valid range, unit), verifiers and
  constraints.

  Both run inside the active generation's read lock, like request authoring,
  so what the console shows is exactly what a request would be validated
  against. With no active generation they return `{:ok, :not_active}`.
  """

  alias Cadence.Commanding.RequestValidation
  alias Cadence.MissionModels
  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.CatalogDeclarations
  alias Cadence.Reads.MissionModels.ActiveBasis

  @default_limit 100
  @max_limit 500

  @type list_opts :: %{
          optional(:query) => binary() | nil,
          optional(:after) => binary() | nil,
          optional(:limit) => pos_integer()
        }

  @doc "Paged command entries; `:after` is the last command id of the previous page."
  @spec list(binary(), binary(), list_opts()) :: {:ok, map() | :not_active} | {:error, term()}
  def list(organization_id, mission_id, opts \\ %{}) do
    limit = opts |> Map.get(:limit, @default_limit) |> min(@max_limit)
    query = opts |> Map.get(:query) |> normalize_query()
    after_id = Map.get(opts, :after) || ""

    with_catalog(organization_id, mission_id, fn snapshot ->
      bindings = bindings(snapshot.catalog)

      matching =
        snapshot.catalog.runtime_definitions
        |> Enum.filter(&(&1.command_id > after_id and matches?(&1, bindings, query)))
        |> Enum.sort_by(& &1.command_id)
        |> Enum.take(limit + 1)

      page = Enum.take(matching, limit)

      {:ok,
       Map.merge(basis(snapshot, organization_id, mission_id), %{
         commands: Enum.map(page, &entry(&1, Map.get(bindings, &1.command_id))),
         next_after: if(length(matching) > limit, do: List.last(page).command_id)
       })}
    end)
  end

  @doc "One command with arguments, verifiers and constraints."
  @spec fetch(binary(), binary(), binary()) ::
          {:ok, map() | :not_active} | {:error, :command_not_found | term()}
  def fetch(organization_id, mission_id, command_id) do
    with_catalog(organization_id, mission_id, fn snapshot ->
      case Enum.find(snapshot.catalog.runtime_definitions, &(&1.command_id == command_id)) do
        nil ->
          {:error, :command_not_found}

        definition ->
          binding = Map.get(bindings(snapshot.catalog), command_id)

          {:ok,
           Map.merge(basis(snapshot, organization_id, mission_id), %{
             command: detail(organization_id, mission_id, definition, binding, snapshot.catalog)
           })}
      end
    end)
  end

  defp with_catalog(organization_id, mission_id, operation) do
    case ActiveBasis.with_command_catalog(organization_id, mission_id, operation) do
      {:error, :command_authoring_basis_unavailable} -> {:ok, :not_active}
      {:error, {:mission_model_runtime_plan_required, :command}} -> {:ok, :not_active}
      other -> other
    end
  end

  defp basis(snapshot, organization_id, mission_id) do
    %{
      revision_id: snapshot.basis.mission_model_revision_id,
      catalog_revision:
        catalog_revision(organization_id, mission_id, snapshot.basis.mission_model_revision_id),
      plan_id: snapshot.catalog.plan_id,
      activation_id: snapshot.activation_id
    }
  end

  @doc """
  The human catalog revision ("rev 14") that produced a mission-model revision,
  as `%{id, number, label}`, or `nil` when no catalog revision records it.
  """
  @spec catalog_revision(binary(), binary(), binary() | nil) :: map() | nil
  def catalog_revision(_org, _mission, nil), do: nil

  def catalog_revision(org, mission, model_revision_id) do
    org
    |> Cadence.Catalog.list_revisions(mission)
    |> Enum.find(&(&1.mission_model_revision_id == model_revision_id))
    |> case do
      nil ->
        nil

      revision ->
        %{
          id: revision.catalog_revision_id,
          number: revision.revision_number,
          label: revision.revision_label
        }
    end
  end

  defp bindings(catalog), do: Map.new(catalog.operational_bindings, &{&1.command_id, &1})

  defp entry(definition, binding) do
    binding = binding || %{}

    %{
      id: definition.command_id,
      name: definition.name,
      display_name: definition.display_name,
      description: definition.description,
      subsystem: Map.get(binding, :subsystem),
      group: Map.get(binding, :group_name),
      significance: Map.get(binding, :significance),
      critical: Map.get(binding, :critical, false),
      hazardous: Map.get(binding, :hazardous, false),
      second_go_required:
        RequestValidation.approval_required?(
          Map.get(binding, :significance),
          Map.get(binding, :critical, false),
          Map.get(binding, :hazardous, false),
          Map.get(binding, :release_policy_hint)
        ),
      argument_count: length(definition.argument_specs)
    }
  end

  defp detail(organization_id, mission_id, definition, binding, catalog) do
    ids = Enum.map(definition.argument_specs, & &1.argument_id)
    revision_id = definition.mission_model_revision_id

    choices =
      case MissionModels.command_argument_choices(
             organization_id,
             mission_id,
             revision_id,
             definition.argument_specs
             |> Enum.filter(&(&1.base_type == :enumerated))
             |> Enum.map(& &1.argument_id)
           ) do
        {:ok, found} -> found
        {:error, _unavailable} -> %{}
      end

    declarations = CatalogDeclarations.closure(organization_id, mission_id, revision_id, ids)
    plans = Enum.filter(catalog.verifier_plans, &(&1.command_id == definition.command_id))
    current = current_points(organization_id, mission_id, plans)

    definition
    |> entry(binding)
    |> Map.merge(%{
      opcode: definition.opcode,
      apid: definition.apid,
      service_type: definition.service_type,
      service_subtype: definition.service_subtype,
      release_policy_hint: binding && binding.release_policy_hint,
      arguments:
        Enum.map(
          definition.argument_specs,
          &Map.put(argument(&1, choices, declarations), :current_point, current[&1.argument_id])
        ),
      verifiers: Enum.map(plans, &verifier/1),
      constraints:
        catalog.constraint_plans
        |> Enum.filter(&(&1.command_id == definition.command_id))
        |> Enum.map(&constraint/1)
    })
  end

  defp argument(spec, choices, declarations) do
    facts = CatalogDeclarations.argument_facts(declarations, spec.argument_id)
    display_unit = get_in(spec.metadata || %{}, ["display_unit"])

    %{
      id: spec.argument_id,
      name: spec.name,
      description: spec.description,
      type: spec.base_type,
      required: spec.required,
      default_value: spec.default_value,
      fixed_value: spec.fixed_value,
      hazardous_values: spec.hazardous_values || [],
      choices: Map.get(choices, spec.argument_id, []),
      valid_range: facts.valid_range,
      unit: facts.unit || blank_to_nil(display_unit)
    }
  end

  # Compose B2 "Now" (fe-ops): the point whose value is an argument's current setting, from a
  # verifier that checks the point equals the value sent (SET_MODE: HK.sc_mode == mode).
  defp current_points(_org, _mission, []), do: %{}

  defp current_points(org, mission, plans) do
    pairs =
      plans
      |> Enum.flat_map(&[&1.success_criteria, &1.failure_criteria])
      |> Enum.flat_map(&argument_points/1)
      |> Enum.reverse()
      |> Map.new()

    if pairs == %{} do
      %{}
    else
      # #73: a mission-model verifier names the parameter's semantic id; resolve it to the
      # catalog point the samples are keyed by. An unknown subject stays as is (no unit).
      points = PointCatalog.list_points(org, mission)

      Map.new(pairs, fn {arg, subject} -> {arg, current_point(points, subject)} end)
    end
  end

  defp current_point(points, subject) do
    case PointCatalog.resolve(points, subject) do
      nil -> %{id: subject, name: subject, unit: nil}
      point -> %{id: point.point_id, name: point.point_id, unit: point.unit}
    end
  end

  defp argument_points(
         %{value_from_argument: arg, subject_ref: point, comparison: :equal} = criteria
       )
       when is_binary(arg) and is_binary(point),
       do: [{arg, point} | Enum.flat_map(criteria.conditions || [], &argument_points/1)]

  defp argument_points(%{conditions: conditions}) when is_list(conditions),
    do: Enum.flat_map(conditions, &argument_points/1)

  defp argument_points(_criteria), do: []

  defp verifier(plan) do
    %{
      id: plan.verifier_id,
      name: plan.name,
      description: plan.description,
      phase: plan.phase,
      timeout_ms: plan.timeout_ms,
      delay_ms: plan.delay_ms,
      severity: plan.severity
    }
  end

  defp constraint(plan) do
    %{
      id: plan.constraint_id,
      name: plan.name,
      description: plan.description,
      type: plan.constraint_type,
      blocking: plan.blocking,
      timeout_ms: plan.timeout_ms
    }
  end

  defp matches?(_definition, _bindings, nil), do: true

  defp matches?(definition, bindings, query) do
    binding = Map.get(bindings, definition.command_id) || %{}

    [
      definition.command_id,
      definition.name,
      definition.display_name,
      definition.description,
      Map.get(binding, :subsystem)
    ]
    |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), query)))
  end

  defp normalize_query(query) when is_binary(query) do
    case query |> String.trim() |> String.downcase() do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_query(_query), do: nil

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
