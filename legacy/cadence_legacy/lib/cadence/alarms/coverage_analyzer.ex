defmodule Cadence.Alarms.CoverageAnalyzer do
  @moduledoc """
  Analyzes alarm rule coverage against Mission Database parameter limits.

  This module helps operators understand:
  - Which parameters have limits but no alarm rules (uncovered)
  - Which alarm rules don't match any current parameters (orphaned)
  - Which parameters' limits have changed since their rules were created

  ## Usage

      # Get full coverage analysis for a definition set (database view)
      {:ok, analysis} = CoverageAnalyzer.analyze(definition_set_id, mission_id)

      # Get coverage analysis for a specific target
      {:ok, analysis} = CoverageAnalyzer.analyze_for_target(target_id)

      # analysis contains:
      %{
        covered: [%{parameter: ..., rules: [...]}],
        uncovered: [%{qualified_name: ..., parameter: ..., limits: ...}],
        orphaned_rules: [%{rule: ..., reason: ...}],
        targets_using_database: [%Target{}, ...],  # only in database view
        target: %Target{}  # only in target view
      }

  ## View Modes

  - **Database view** (`analyze/2`): Shows coverage across all targets using a
    definition set. Rules for OTHER targets using different databases appear
    as "orphaned" only if they reference parameters not in THIS database.

  - **Target view** (`analyze_for_target/1`): Shows coverage for a specific
    target, including both mission-wide rules and target-specific rules.

  ## Integration Points

  Call this after:
  - A new DefinitionSet is published
  - An AlarmRule is created/modified/deleted
  - On-demand from the UI to review coverage
  """

  import Ecto.Query

  alias Cadence.Alarms.AlarmRule
  alias Cadence.MissionDatabase.{Container, ContainerEntry, DataType, DefinitionSet, Parameter}
  alias Cadence.Repo
  alias Cadence.Targets
  alias Cadence.Targets.Target

  @type parameter_with_limits :: %{
          qualified_name: String.t(),
          parameter: Parameter.t(),
          data_type: DataType.t(),
          container_name: String.t()
        }

  @type coverage_result :: %{
          covered: [%{parameter: parameter_with_limits(), rules: [AlarmRule.t()]}],
          uncovered: [parameter_with_limits()],
          orphaned_rules: [%{rule: AlarmRule.t(), reason: atom()}]
        }

  @doc """
  Analyzes alarm rule coverage for a definition set (database view).

  Returns a map with:
  - `covered`: Parameters with limits that have matching alarm rules
  - `uncovered`: Parameters with limits but no matching alarm rules
  - `orphaned_rules`: Alarm rules that don't match any current parameters
  - `targets_using_database`: List of targets using this definition set
  """
  @spec analyze(String.t(), String.t()) :: {:ok, coverage_result()} | {:error, term()}
  def analyze(definition_set_id, mission_id) do
    with {:ok, definition_set} <- get_definition_set(definition_set_id),
         {:ok, parameters_with_limits} <- get_parameters_with_limits(definition_set),
         {:ok, rules} <- get_alarm_rules(mission_id) do
      targets_using_database = Targets.list_targets_by_definition_set(definition_set_id)
      target_ids_using_this_db = MapSet.new(targets_using_database, & &1.id)

      analysis =
        perform_analysis(parameters_with_limits, rules, %{
          target_ids_using_database: target_ids_using_this_db
        })

      {:ok, Map.put(analysis, :targets_using_database, targets_using_database)}
    end
  end

  @doc """
  Analyzes alarm rule coverage for a specific target.

  This shows coverage from the target's perspective, including:
  - Mission-wide rules (no target_id)
  - Target-specific rules for this target

  Rules for other targets are excluded from the analysis.
  """
  @spec analyze_for_target(String.t()) :: {:ok, coverage_result()} | {:error, term()}
  def analyze_for_target(target_id) do
    with {:ok, target} <- get_target(target_id),
         {:ok, definition_set} <- get_definition_set(target.definition_set_id),
         {:ok, parameters_with_limits} <- get_parameters_with_limits(definition_set),
         {:ok, rules} <- get_alarm_rules_for_target(target.mission_id, target_id) do
      analysis = perform_analysis(parameters_with_limits, rules, %{target_id: target_id})
      {:ok, Map.put(analysis, :target, target)}
    end
  end

  defp get_target(target_id) do
    case Repo.get(Target, target_id) do
      nil -> {:error, :target_not_found}
      target -> {:ok, target}
    end
  end

  defp get_alarm_rules_for_target(mission_id, target_id) do
    # Get rules that apply to this target:
    # - Mission-wide rules (target_id is nil)
    # - Target-specific rules for this target
    rules =
      from(r in AlarmRule,
        where: r.mission_id == ^mission_id,
        where: r.event_type == "telemetry_limit",
        where: r.enabled == true,
        where: is_nil(r.target_id) or r.target_id == ^target_id
      )
      |> Repo.all()

    {:ok, rules}
  end

  @doc """
  Returns only the uncovered parameters (parameters with limits but no rules).

  This is a convenience function for quickly identifying coverage gaps.
  """
  @spec get_uncovered(String.t(), String.t()) ::
          {:ok, [parameter_with_limits()]} | {:error, term()}
  def get_uncovered(definition_set_id, mission_id) do
    case analyze(definition_set_id, mission_id) do
      {:ok, %{uncovered: uncovered}} -> {:ok, uncovered}
      error -> error
    end
  end

  @doc """
  Returns a summary of coverage statistics.
  """
  @spec summary(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def summary(definition_set_id, mission_id) do
    case analyze(definition_set_id, mission_id) do
      {:ok, analysis} ->
        summary = %{
          total_parameters_with_limits: length(analysis.covered) + length(analysis.uncovered),
          covered_count: length(analysis.covered),
          uncovered_count: length(analysis.uncovered),
          orphaned_rules_count: length(analysis.orphaned_rules),
          coverage_percentage:
            calculate_coverage_percentage(
              length(analysis.covered),
              length(analysis.uncovered)
            )
        }

        {:ok, summary}

      error ->
        error
    end
  end

  # Private functions

  defp get_definition_set(definition_set_id) do
    case Repo.get(DefinitionSet, definition_set_id) do
      nil -> {:error, :definition_set_not_found}
      definition_set -> {:ok, definition_set}
    end
  end

  defp get_parameters_with_limits(definition_set) do
    # Query all containers with their entries, parameters, and data types
    # Filter to only parameters whose data_type has limits defined
    query =
      from c in Container,
        where: c.definition_set_id == ^definition_set.id,
        join: ce in ContainerEntry,
        on: ce.container_id == c.id,
        join: p in Parameter,
        on: p.id == ce.parameter_id or p.name == ce.parameter_ref,
        join: dt in DataType,
        on: dt.id == p.data_type_id or dt.name == p.data_type_ref,
        where: dt.definition_set_id == ^definition_set.id,
        where: not is_nil(dt.default_alarm),
        select: %{
          container_name: c.name,
          parameter: p,
          data_type: dt,
          entry: ce
        }

    results = Repo.all(query)

    parameters_with_limits =
      results
      |> Enum.map(fn %{container_name: container_name, parameter: param, data_type: dt} ->
        %{
          qualified_name: "#{container_name}.#{param.name}",
          parameter: param,
          data_type: dt,
          container_name: container_name
        }
      end)
      |> Enum.uniq_by(& &1.qualified_name)

    {:ok, parameters_with_limits}
  end

  defp get_alarm_rules(mission_id) do
    rules =
      from(r in AlarmRule,
        where: r.mission_id == ^mission_id,
        where: r.event_type == "telemetry_limit",
        where: r.enabled == true
      )
      |> Repo.all()

    {:ok, rules}
  end

  defp perform_analysis(parameters_with_limits, rules, context) do
    # For each parameter, find matching rules
    {covered, uncovered} =
      parameters_with_limits
      |> Enum.reduce({[], []}, fn param, {covered_acc, uncovered_acc} ->
        matching_rules = find_matching_rules(param, rules)

        if Enum.empty?(matching_rules) do
          {covered_acc, [param | uncovered_acc]}
        else
          {[%{parameter: param, rules: matching_rules} | covered_acc], uncovered_acc}
        end
      end)

    # Find orphaned rules (rules that don't match any parameter)
    all_qualified_names = MapSet.new(parameters_with_limits, & &1.qualified_name)
    orphaned_rules = find_orphaned_rules(rules, all_qualified_names, context)

    %{
      covered: Enum.reverse(covered),
      uncovered: Enum.reverse(uncovered),
      orphaned_rules: orphaned_rules
    }
  end

  defp find_matching_rules(param, rules) do
    Enum.filter(rules, fn rule ->
      rule_matches_parameter?(rule, param.qualified_name)
    end)
  end

  defp rule_matches_parameter?(rule, qualified_name) do
    conditions = rule.conditions || %{}

    # A rule matches if it has no item conditions (matches all)
    # OR if its item conditions match this parameter
    cond do
      # No item-specific conditions - matches all items
      not has_item_conditions?(conditions) ->
        true

      # Has exact item_name list - check membership
      Map.has_key?(conditions, "item_name") ->
        qualified_name in (conditions["item_name"] || [])

      # Has item_name_pattern - check regex match
      Map.has_key?(conditions, "item_name_pattern") ->
        pattern = conditions["item_name_pattern"]
        matches_pattern?(qualified_name, pattern)

      true ->
        false
    end
  end

  defp has_item_conditions?(conditions) do
    Map.has_key?(conditions, "item_name") or Map.has_key?(conditions, "item_name_pattern")
  end

  defp matches_pattern?(qualified_name, pattern) when is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, qualified_name)
      {:error, _} -> false
    end
  end

  defp matches_pattern?(_, _), do: false

  defp find_orphaned_rules(rules, all_qualified_names, context) do
    target_ids_using_this_db = Map.get(context, :target_ids_using_database, nil)

    rules
    |> Enum.flat_map(fn rule ->
      case orphaned_reason(rule, all_qualified_names, target_ids_using_this_db) do
        nil -> []
        reason -> [%{rule: rule, reason: reason}]
      end
    end)
  end

  defp orphaned_reason(rule, all_qualified_names, target_ids_using_this_db) do
    conditions = rule.conditions || %{}

    with false <- skip_target_rule?(rule, target_ids_using_this_db),
         true <- has_item_conditions?(conditions) do
      check_item_conditions(conditions, all_qualified_names)
    else
      _ -> nil
    end
  end

  defp check_item_conditions(conditions, all_qualified_names) do
    cond do
      Map.has_key?(conditions, "item_name") ->
        item_names = conditions["item_name"] || []

        if Enum.any?(item_names, &MapSet.member?(all_qualified_names, &1)) do
          nil
        else
          :item_not_found
        end

      Map.has_key?(conditions, "item_name_pattern") ->
        pattern = conditions["item_name_pattern"]

        if Enum.any?(all_qualified_names, &matches_pattern?(&1, pattern)) do
          nil
        else
          :pattern_no_matches
        end

      true ->
        nil
    end
  end

  defp skip_target_rule?(%{target_id: _target_id}, nil), do: false

  defp skip_target_rule?(%{target_id: nil}, _target_ids_using_this_db), do: false

  defp skip_target_rule?(%{target_id: target_id}, target_ids_using_this_db) do
    not MapSet.member?(target_ids_using_this_db, target_id)
  end

  defp calculate_coverage_percentage(covered, uncovered) do
    total = covered + uncovered

    if total == 0 do
      100.0
    else
      Float.round(covered / total * 100, 1)
    end
  end
end
