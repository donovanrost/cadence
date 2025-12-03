defmodule Cadence.Alarms.RuleSuggester do
  @moduledoc """
  Generates suggested alarm rules for parameters with limits but no coverage.

  This module helps operators quickly create sensible default alarm rules
  for uncovered parameters, reducing the manual work of setting up alarm
  coverage for a mission.

  ## Suggestion Strategies

  The suggester supports pluggable strategies for generating suggestions:

  - `:default` - Basic two-rule strategy (critical/warning pairs)
  - `:semantic` - Intelligent strategy that analyzes parameter naming patterns
    and data types to generate context-aware suggestions

  ## Usage

      # Get suggested rules using semantic strategy (default)
      {:ok, suggestions} = RuleSuggester.suggest(definition_set_id, mission_id)

      # Use basic strategy
      {:ok, suggestions} = RuleSuggester.suggest(definition_set_id, mission_id, strategy: :default)

      # Create all suggested rules
      {:ok, rules} = RuleSuggester.create_suggested_rules(definition_set_id, mission_id)

      # Create rules for specific parameters only
      {:ok, rules} = RuleSuggester.create_suggested_rules(definition_set_id, mission_id,
        parameters: ["HEALTH.cpu_temp", "POWER.battery_voltage"]
      )

  ## Suggested Rule Structure

  Each suggested rule includes:
  - Matches the specific parameter by `item_name`
  - Severity based on limit state and strategy analysis
  - Context-aware message template
  - Rationale explaining why the suggestion was made (semantic strategy)
  - Confidence score for suggestion appropriateness
  - No notification channels (operator must configure)
  """

  alias Cadence.Repo
  alias Cadence.Alarms.{AlarmRule, CoverageAnalyzer}
  alias Cadence.Missions.Mission

  @default_strategy Cadence.Alarms.SuggestionStrategy.Semantic

  @strategies %{
    default: Cadence.Alarms.SuggestionStrategy.Default,
    semantic: Cadence.Alarms.SuggestionStrategy.Semantic
  }

  @type suggestion :: %{
          name: String.t(),
          event_type: String.t(),
          conditions: map(),
          severity: atom(),
          message_template: String.t(),
          parameter: map(),
          rationale: String.t() | nil,
          confidence: float()
        }

  @doc """
  Generates suggested alarm rules for uncovered parameters.

  Returns a list of suggested rule attributes (not yet persisted).
  Suggestions are generated using the configured strategy.

  ## Options

  - `:strategy` - Strategy to use: `:default` or `:semantic` (default: `:semantic`)
  - `:parameters` - List of qualified names to filter to
  - `:min_confidence` - Minimum confidence score to include (default: 0.0)
  - `:target_id` - Target ID for target-specific analysis and rules (optional)
  """
  @spec suggest(String.t(), String.t(), keyword()) :: {:ok, [suggestion()]} | {:error, term()}
  def suggest(definition_set_id, mission_id, opts \\ []) do
    target_id = Keyword.get(opts, :target_id)

    with {:ok, mission} <- get_mission(mission_id),
         {:ok, uncovered} <- get_uncovered_for_context(definition_set_id, mission_id, target_id) do
      strategy_key = Keyword.get(opts, :strategy, :semantic)
      strategy = Map.get(@strategies, strategy_key, @default_strategy)
      parameters_filter = Keyword.get(opts, :parameters)
      min_confidence = Keyword.get(opts, :min_confidence, 0.0)

      context = %{
        mission_id: mission_id,
        organization_id: mission.organization_id,
        definition_set_id: definition_set_id,
        target_id: target_id
      }

      suggestions =
        uncovered
        |> maybe_filter_parameters(parameters_filter)
        |> Enum.flat_map(fn param ->
          strategy.suggest(param, context)
        end)
        |> Enum.filter(fn suggestion ->
          Map.get(suggestion, :confidence, 1.0) >= min_confidence
        end)

      {:ok, suggestions}
    end
  end

  defp get_uncovered_for_context(definition_set_id, mission_id, nil) do
    CoverageAnalyzer.get_uncovered(definition_set_id, mission_id)
  end

  defp get_uncovered_for_context(_definition_set_id, _mission_id, target_id) do
    case CoverageAnalyzer.analyze_for_target(target_id) do
      {:ok, %{uncovered: uncovered}} -> {:ok, uncovered}
      error -> error
    end
  end

  @doc """
  Returns available suggestion strategies.
  """
  def available_strategies do
    Enum.map(@strategies, fn {key, module} ->
      %{
        key: key,
        name: module.name(),
        description: module.description()
      }
    end)
  end

  @doc """
  Creates alarm rules for uncovered parameters.

  ## Options

  - `:parameters` - List of qualified names to create rules for (default: all uncovered)
  - `:severity_filter` - Only create rules for specific severities, e.g. `[:critical]`
  - `:dry_run` - If true, returns changesets without inserting (default: false)
  - `:target_id` - Target ID for target-specific rules (optional, nil for mission-wide)

  ## Returns

  `{:ok, created_rules}` on success, where `created_rules` is a list of the
  newly created AlarmRule structs.
  """
  @spec create_suggested_rules(String.t(), String.t(), keyword()) ::
          {:ok, [AlarmRule.t()]} | {:error, term()}
  def create_suggested_rules(definition_set_id, mission_id, opts \\ []) do
    target_id = Keyword.get(opts, :target_id)

    with {:ok, mission} <- get_mission(mission_id),
         {:ok, suggestions} <- suggest(definition_set_id, mission_id, opts) do
      severity_filter = Keyword.get(opts, :severity_filter)
      dry_run = Keyword.get(opts, :dry_run, false)

      suggestions =
        if severity_filter do
          Enum.filter(suggestions, &(&1.severity in severity_filter))
        else
          suggestions
        end

      if dry_run do
        changesets =
          Enum.map(suggestions, fn suggestion ->
            build_rule_changeset(mission, suggestion, target_id)
          end)

        {:ok, changesets}
      else
        create_rules(mission, suggestions, target_id)
      end
    end
  end

  @doc """
  Generates a preview of what rules would be created.

  Returns formatted descriptions of each suggested rule.
  """
  @spec preview(String.t(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def preview(definition_set_id, mission_id, opts \\ []) do
    case suggest(definition_set_id, mission_id, opts) do
      {:ok, suggestions} ->
        previews =
          Enum.map(suggestions, fn s ->
            """
            Rule: #{s.name}
              Severity: #{s.severity}
              Conditions: limit_state = #{inspect(s.conditions["limit_state"])}
              Item: #{hd(s.conditions["item_name"])}
              Message: #{s.message_template}
            """
          end)

        {:ok, previews}

      error ->
        error
    end
  end

  # Private functions

  defp get_mission(mission_id) do
    case Repo.get(Mission, mission_id) do
      nil -> {:error, :mission_not_found}
      mission -> {:ok, mission}
    end
  end

  defp maybe_filter_parameters(uncovered, nil), do: uncovered

  defp maybe_filter_parameters(uncovered, qualified_names) when is_list(qualified_names) do
    names_set = MapSet.new(qualified_names)
    Enum.filter(uncovered, &MapSet.member?(names_set, &1.qualified_name))
  end

  defp build_rule_changeset(mission, suggestion, target_id) do
    attrs = %{
      organization_id: mission.organization_id,
      mission_id: mission.id,
      target_id: target_id,
      name: suggestion.name,
      event_type: suggestion.event_type,
      conditions: suggestion.conditions,
      severity: suggestion.severity,
      message_template: suggestion.message_template,
      enabled: true,
      notification_channels: []
    }

    AlarmRule.changeset(%AlarmRule{}, attrs)
  end

  defp create_rules(mission, suggestions, target_id) do
    results =
      Enum.reduce_while(suggestions, {:ok, []}, fn suggestion, {:ok, acc} ->
        changeset = build_rule_changeset(mission, suggestion, target_id)

        case Repo.insert(changeset) do
          {:ok, rule} ->
            {:cont, {:ok, [rule | acc]}}

          {:error, changeset} ->
            {:halt, {:error, {:insert_failed, suggestion.name, changeset}}}
        end
      end)

    case results do
      {:ok, rules} -> {:ok, Enum.reverse(rules)}
      error -> error
    end
  end
end
