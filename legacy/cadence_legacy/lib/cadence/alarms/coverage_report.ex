defmodule Cadence.Alarms.CoverageReport do
  @moduledoc """
  Generates coverage reports when a new DefinitionSet is published.

  This module provides the integration point between the Mission Database
  lifecycle and the alarm coverage analysis system.

  ## Report Contents

  A coverage report includes:
  - Summary statistics (total, covered, uncovered counts)
  - List of newly uncovered parameters (items with limits but no rules)
  - List of orphaned rules (rules that no longer match any items)
  - Diff of limit changes (if comparing to a previous version)

  ## Usage

      # Generate report after publishing a new DefinitionSet
      {:ok, report} = CoverageReport.generate(mission_id)

      # Generate report comparing two versions
      {:ok, report} = CoverageReport.compare_versions(mission_id, old_version, new_version)

  ## Integration

  This is designed to be called after `DefinitionSet.publish/1` to provide
  operators with visibility into alarm coverage gaps.
  """

  alias Cadence.Alarms.CoverageAnalyzer
  alias Cadence.MissionDatabase.DefinitionSet
  alias Cadence.Repo

  @type report :: %{
          generated_at: DateTime.t(),
          definition_set_id: String.t(),
          definition_set_version: String.t(),
          summary: map(),
          uncovered_parameters: list(),
          orphaned_rules: list(),
          suggestions_available: boolean()
        }

  @doc """
  Generates a coverage report for a specific DefinitionSet.
  """
  @spec generate(String.t(), String.t()) :: {:ok, report()} | {:error, term()}
  def generate(definition_set_id, mission_id) do
    with {:ok, definition_set} <- get_definition_set(definition_set_id),
         {:ok, analysis} <- CoverageAnalyzer.analyze(definition_set_id, mission_id),
         {:ok, summary} <- CoverageAnalyzer.summary(definition_set_id, mission_id) do
      report = %{
        generated_at: Cadence.Time.now(),
        definition_set_id: definition_set.id,
        definition_set_version: definition_set.version,
        summary: summary,
        uncovered_parameters:
          Enum.map(analysis.uncovered, fn param ->
            %{
              qualified_name: param.qualified_name,
              container: param.container_name,
              parameter_name: param.parameter.name,
              has_limits: true
            }
          end),
        orphaned_rules:
          Enum.map(analysis.orphaned_rules, fn %{rule: rule, reason: reason} ->
            %{
              rule_id: rule.id,
              rule_name: rule.name,
              reason: reason,
              conditions: rule.conditions
            }
          end),
        suggestions_available: length(analysis.uncovered) > 0
      }

      {:ok, report}
    end
  end

  @doc """
  Generates a diff report comparing limits between two DefinitionSet versions.

  Useful for understanding what changed when a new C&T database is imported.
  """
  @spec compare_versions(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def compare_versions(database_id, old_version, new_version) do
    with {:ok, old_ds} <- get_definition_set_by_version(database_id, old_version),
         {:ok, new_ds} <- get_definition_set_by_version(database_id, new_version),
         {:ok, old_params} <- get_parameters_with_limits_for_ds(old_ds),
         {:ok, new_params} <- get_parameters_with_limits_for_ds(new_ds) do
      old_by_name = Map.new(old_params, &{&1.qualified_name, &1})
      new_by_name = Map.new(new_params, &{&1.qualified_name, &1})

      old_names = MapSet.new(Map.keys(old_by_name))
      new_names = MapSet.new(Map.keys(new_by_name))

      added = MapSet.difference(new_names, old_names) |> MapSet.to_list()
      removed = MapSet.difference(old_names, new_names) |> MapSet.to_list()

      # Find items where limits changed
      common = MapSet.intersection(old_names, new_names) |> MapSet.to_list()

      changed =
        common
        |> Enum.filter(fn name ->
          old_limits = get_in(old_by_name, [name, :data_type, :default_alarm])
          new_limits = get_in(new_by_name, [name, :data_type, :default_alarm])
          old_limits != new_limits
        end)
        |> Enum.map(fn name ->
          %{
            qualified_name: name,
            old_limits: get_in(old_by_name, [name, :data_type, :default_alarm]),
            new_limits: get_in(new_by_name, [name, :data_type, :default_alarm])
          }
        end)

      diff = %{
        generated_at: Cadence.Time.now(),
        old_version: old_version,
        new_version: new_version,
        summary: %{
          added_count: length(added),
          removed_count: length(removed),
          changed_count: length(changed)
        },
        added_parameters: Enum.map(added, &Map.get(new_by_name, &1)),
        removed_parameters: Enum.map(removed, &Map.get(old_by_name, &1)),
        changed_limits: changed
      }

      {:ok, diff}
    end
  end

  @doc """
  Convenience function to publish a DefinitionSet and return a coverage report.

  This wraps `DefinitionSet.publish/1` and generates a coverage report,
  making it easy to show operators the alarm coverage impact.

  Note: You must provide the mission_id since DefinitionSets no longer have direct mission association.
  """
  @spec publish_with_report(DefinitionSet.t(), String.t()) ::
          {:ok, %{definition_set: DefinitionSet.t(), report: report()}} | {:error, term()}
  def publish_with_report(%DefinitionSet{} = definition_set, mission_id) do
    with {:ok, published_ds} <- DefinitionSet.publish(definition_set),
         {:ok, report} <- generate(published_ds.id, mission_id) do
      {:ok, %{definition_set: published_ds, report: report}}
    end
  end

  # Private functions

  defp get_definition_set(definition_set_id) do
    case Repo.get(DefinitionSet, definition_set_id) do
      nil -> {:error, :definition_set_not_found}
      ds -> {:ok, ds}
    end
  end

  defp get_definition_set_by_version(database_id, version) do
    case DefinitionSet.get_by_version(database_id, version) do
      nil -> {:error, {:version_not_found, version}}
      ds -> {:ok, ds}
    end
  end

  defp get_parameters_with_limits_for_ds(definition_set) do
    # Reuse the CoverageAnalyzer's query logic
    # This is a simplified version - in practice you might want to refactor
    # CoverageAnalyzer to accept a definition_set directly
    import Ecto.Query

    alias Cadence.MissionDatabase.{Container, ContainerEntry, DataType, Parameter}
    alias Cadence.Repo

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
          data_type: dt
        }

    results = Repo.all(query)

    parameters =
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

    {:ok, parameters}
  end
end
