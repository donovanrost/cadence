defmodule Cadence.DerivedTelemetry do
  @moduledoc """
  Evaluates mission-scoped derived telemetry definitions over the canonical
  telemetry sample log.
  """

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.DerivedTelemetry.{Definition, ExpressionEvaluator, Run, Sample}
  alias Cadence.DerivedTelemetry.EvaluationRunRow, as: DerivedTelemetryEvaluationRunRow
  alias Cadence.Jobs
  alias Cadence.MissionModels.LegacyGuard

  alias Cadence.DerivedTelemetry.Store
  alias Cadence.Repo
  alias Cadence.Telemetry.Sample, as: TelemetrySample
  alias Cadence.Telemetry.SampleRecords

  @mission_scope_key "__mission__"

  @spec evaluate(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def evaluate(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    with :ok <- LegacyGuard.ensure_available(mission_id),
         {:ok, definitions} <- definitions_from_opts(mission_id, opts),
         run = build_run(mission_id, definitions, opts),
         {:ok, persisted_run} <- insert_run(run) do
      execute_run(persisted_run, Keyword.put(opts, :definitions, definitions))
    end
  end

  @spec start_evaluate(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def start_evaluate(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    with :ok <- LegacyGuard.ensure_available(mission_id),
         {:ok, definitions} <- definitions_from_opts(mission_id, opts),
         run = build_run(mission_id, definitions, opts),
         {:ok, %Run{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :derived_telemetry_evaluation,
             mission_id,
             persisted_run.derived_run_id,
             %{"derived_run_id" => persisted_run.derived_run_id}
           ) do
        {:ok, _job} ->
          {:ok, persisted_run}

        {:error, reason} ->
          failed_run =
            %Run{
              persisted_run
              | status: :failed,
                failure_reason: {:job_enqueue_failed, reason},
                completed_at: DateTime.utc_now()
            }

          _ = update_run(failed_run)
          {:error, reason}
      end
    end
  end

  @spec fetch_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def fetch_run(derived_run_id) when is_binary(derived_run_id) do
    case Repo.get(DerivedTelemetryEvaluationRunRow, derived_run_id) do
      nil ->
        {:error, :derived_run_not_found}

      %DerivedTelemetryEvaluationRunRow{} = run_row ->
        {:ok, DerivedTelemetryEvaluationRunRow.to_domain(run_row)}
    end
  end

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def execute_enqueued_run(derived_run_id) when is_binary(derived_run_id) do
    with {:ok, %Run{} = run} <- fetch_run(derived_run_id),
         :ok <- LegacyGuard.ensure_available(run.mission_id),
         {:ok, opts} <- opts_from_run(run) do
      execute_run(run, opts)
    end
  end

  defp build_run(mission_id, definitions, opts) do
    Run.new(%{
      mission_id: mission_id,
      metadata: %{
        "spacecraft_id" => Keyword.get(opts, :spacecraft_id),
        "definition_snapshot" => Enum.map(definitions, &definition_snapshot/1)
      }
    })
  end

  defp execute_run(%Run{} = run, opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    definitions = Keyword.fetch!(opts, :definitions)

    with {:ok, evaluation_plan} <- build_evaluation_plan(definitions),
         {:ok, telemetry_samples} <- fetch_source_samples(run.mission_id, spacecraft_id),
         {:ok, derived_samples} <- derive_samples(telemetry_samples, evaluation_plan) do
      completed_run =
        %Run{
          run
          | status: :completed,
            evaluated_sample_count: length(telemetry_samples),
            emitted_sample_count: length(derived_samples),
            definition_count: length(evaluation_plan.ordered_definitions),
            completed_at: DateTime.utc_now()
        }

      persist_completed_run(completed_run, derived_samples)
    else
      {:error, reason} ->
        failed_run =
          %Run{
            run
            | status: :failed,
              failure_reason: reason,
              completed_at: DateTime.utc_now()
          }

        _ = update_run(failed_run)
        {:error, reason}
    end
  end

  defp fetch_source_samples(mission_id, spacecraft_id) do
    samples =
      SampleRecords.list_samples(mission_id,
        spacecraft_id: spacecraft_id,
        order: :receipt_asc
      )

    {:ok, samples}
  end

  defp derive_samples(telemetry_samples, evaluation_plan) do
    telemetry_samples
    |> Enum.reduce_while({:ok, {%{}, []}}, fn %TelemetrySample{} = telemetry_sample,
                                              {:ok, {latest_by_point, derived_samples_rev}} ->
      case derive_for_telemetry_sample(telemetry_sample, latest_by_point, evaluation_plan) do
        {:ok, {updated_latest_by_point, emitted_samples}} ->
          {:cont,
           {:ok, {updated_latest_by_point, Enum.reverse(emitted_samples) ++ derived_samples_rev}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {_latest_by_point, derived_samples_rev}} -> {:ok, Enum.reverse(derived_samples_rev)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp derive_for_telemetry_sample(
         %TelemetrySample{} = telemetry_sample,
         latest_by_point,
         evaluation_plan
       ) do
    telemetry_source_sample = telemetry_source_sample(telemetry_sample)

    latest_by_point =
      put_latest_source_sample(latest_by_point, telemetry_source_sample)

    impacted_definitions =
      impacted_definitions(
        telemetry_sample.point_id,
        evaluation_plan.definitions_by_source,
        evaluation_plan.definition_index
      )

    Enum.reduce_while(
      impacted_definitions,
      {:ok, {latest_by_point, []}},
      fn %Definition{} = definition, {:ok, {current_latest_by_point, emitted_samples_rev}} ->
        reduce_emitted_definition_sample(
          definition,
          telemetry_sample,
          telemetry_source_sample,
          current_latest_by_point,
          emitted_samples_rev
        )
      end
    )
    |> case do
      {:ok, {updated_latest_by_point, emitted_samples_rev}} ->
        {:ok, {updated_latest_by_point, Enum.reverse(emitted_samples_rev)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp source_samples_for_definition(latest_by_point, scope_id, source_point_ids) do
    Enum.reduce_while(source_point_ids, {:ok, []}, fn source_point_id, {:ok, acc} ->
      case Map.get(latest_by_point, {scope_id, source_point_id}) do
        nil -> {:halt, :missing}
        sample -> {:cont, {:ok, [sample | acc]}}
      end
    end)
    |> case do
      :missing -> :missing
      {:ok, source_samples} -> {:ok, Enum.reverse(source_samples)}
    end
  end

  defp build_derived_sample(definition, telemetry_sample, source_samples, value) do
    generation_time =
      source_samples
      |> Enum.map(&(&1.generation_time || &1.receipt_time))
      |> Enum.reduce(&later_datetime/2)

    quality_state =
      source_samples
      |> Enum.map(& &1.quality_state)
      |> Enum.max_by(&quality_rank/1)

    source_sample_ids = Enum.map(source_samples, & &1.sample_id)

    %Sample{
      derived_sample_id:
        "derived_sample:" <>
          definition.derived_definition_id <>
          ":v" <> Integer.to_string(definition.version) <> ":" <> telemetry_sample.sample_id,
      mission_id: telemetry_sample.mission_id,
      spacecraft_id: telemetry_sample.spacecraft_id,
      point_id: definition.point_id,
      point_name: definition.point_name,
      derived_definition_id: definition.derived_definition_id,
      derived_definition_version: definition.version,
      trigger_sample_id: telemetry_sample.sample_id,
      value: value,
      quality_state: quality_state,
      generation_time: generation_time,
      receipt_time: telemetry_sample.receipt_time,
      provenance: %{
        "source_sample_ids" => source_sample_ids,
        "source_point_ids" => definition.source_point_ids,
        "trigger_sample_id" => telemetry_sample.sample_id,
        "expression" => definition.expression
      }
    }
  end

  defp persist_completed_run(%Run{} = run, derived_samples) do
    Multi.new()
    |> Multi.run(:derived_run, fn repo, _changes ->
      repo_run_update(repo, run)
    end)
    |> add_sample_inserts(derived_samples)
    |> Multi.run(:derived_telemetry_latest_values, fn repo, _changes ->
      persist_latest_values(repo, derived_samples)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> {:ok, run}
      {:error, _operation, %Changeset{} = changeset, _changes_so_far} -> {:error, changeset}
      {:error, _operation, reason, _changes_so_far} -> {:error, reason}
    end
  end

  defp add_sample_inserts(%Multi{} = multi, derived_samples) do
    Store.add_sample_inserts(multi, derived_samples)
  end

  defp insert_run(%Run{} = run) do
    case Repo.insert(DerivedTelemetryEvaluationRunRow.changeset(run)) do
      {:ok, %DerivedTelemetryEvaluationRunRow{} = run_row} ->
        {:ok, DerivedTelemetryEvaluationRunRow.to_domain(run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case repo_run_update(Repo, run) do
      {:ok, %DerivedTelemetryEvaluationRunRow{} = run_row} ->
        {:ok, DerivedTelemetryEvaluationRunRow.to_domain(run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp repo_run_update(repo, %Run{} = run) do
    case repo.get(DerivedTelemetryEvaluationRunRow, run.derived_run_id) do
      nil ->
        {:error, :derived_run_not_found}

      %DerivedTelemetryEvaluationRunRow{} = run_row ->
        repo.update(DerivedTelemetryEvaluationRunRow.changeset(run_row, run))
    end
  end

  defp opts_from_run(%Run{mission_id: mission_id, metadata: metadata}) when is_map(metadata) do
    snapshot = Map.get(metadata, "definition_snapshot", Map.get(metadata, :definition_snapshot))

    with {:ok, definitions} <- build_definition_snapshot(mission_id, snapshot) do
      opts =
        case Map.get(metadata, "spacecraft_id", Map.get(metadata, :spacecraft_id)) do
          nil -> []
          spacecraft_id -> [spacecraft_id: spacecraft_id]
        end

      {:ok, Keyword.put(opts, :definitions, definitions)}
    end
  end

  defp definitions_from_opts(mission_id, opts) do
    case Keyword.fetch(opts, :definitions) do
      {:ok, definitions} -> build_definition_snapshot(mission_id, definitions)
      :error -> {:error, :derived_definition_snapshot_required}
    end
  end

  defp build_definition_snapshot(mission_id, definitions) when is_list(definitions) do
    Enum.reduce_while(definitions, {:ok, []}, fn definition, {:ok, acc} ->
      with {:ok, %Definition{} = definition} <- build_definition(definition),
           :ok <- validate_definition_mission(definition, mission_id),
           :ok <- Definition.validate(definition) do
        {:cont, {:ok, [definition | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_definition_snapshot(_mission_id, _definitions),
    do: {:error, :invalid_derived_definition_snapshot}

  defp build_definition(%Definition{} = definition), do: {:ok, definition}

  defp build_definition(definition) when is_map(definition) do
    {:ok,
     Definition.new(%{
       derived_definition_id: definition_value(definition, :derived_definition_id),
       mission_id: definition_value(definition, :mission_id),
       point_id: definition_value(definition, :point_id),
       point_name: definition_value(definition, :point_name),
       expression: definition_value(definition, :expression),
       version: definition_value(definition, :version),
       source_point_ids: definition_value(definition, :source_point_ids),
       metadata: definition_value(definition, :metadata)
     })}
  rescue
    KeyError -> {:error, :invalid_derived_definition_snapshot}
  end

  defp build_definition(_definition), do: {:error, :invalid_derived_definition_snapshot}

  defp definition_snapshot(%Definition{} = definition) do
    definition
    |> Map.from_struct()
    |> Map.take([
      :derived_definition_id,
      :mission_id,
      :point_id,
      :point_name,
      :expression,
      :version,
      :source_point_ids,
      :metadata
    ])
  end

  defp definition_value(definition, key) do
    Map.get(definition, key, Map.get(definition, Atom.to_string(key)))
  end

  defp validate_definition_mission(%Definition{mission_id: mission_id}, mission_id), do: :ok

  defp validate_definition_mission(%Definition{} = definition, mission_id) do
    {:error,
     {:derived_definition_mission_mismatch, definition.derived_definition_id, mission_id,
      definition.mission_id}}
  end

  defp build_evaluation_plan(definitions) when is_list(definitions) do
    with :ok <- ensure_unique_output_points(definitions),
         {:ok, ordered_definitions} <- topologically_order_definitions(definitions) do
      definitions_by_source = build_definitions_by_source(ordered_definitions)

      definition_index =
        Map.new(Enum.with_index(ordered_definitions), fn {%Definition{} = definition, index} ->
          {definition.point_id, index}
        end)

      {:ok,
       %{
         ordered_definitions: ordered_definitions,
         definitions_by_source: definitions_by_source,
         definition_index: definition_index
       }}
    end
  end

  defp ensure_unique_output_points(definitions) do
    definitions
    |> Enum.reduce_while(MapSet.new(), fn %Definition{} = definition, seen_points ->
      if MapSet.member?(seen_points, definition.point_id) do
        {:halt, {:error, {:duplicate_derived_point_id, definition.point_id}}}
      else
        {:cont, MapSet.put(seen_points, definition.point_id)}
      end
    end)
    |> case do
      %MapSet{} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp topologically_order_definitions(definitions) do
    definitions_by_output_point =
      Map.new(definitions, fn %Definition{} = definition ->
        {definition.point_id, definition}
      end)

    in_degree =
      Map.new(definitions, fn %Definition{} = definition ->
        dependency_count =
          Enum.count(definition.source_point_ids, &Map.has_key?(definitions_by_output_point, &1))

        {definition.point_id, dependency_count}
      end)

    dependent_points_by_source =
      Enum.reduce(definitions, %{}, fn %Definition{} = definition, acc ->
        Enum.reduce(definition.source_point_ids, acc, fn source_point_id, source_acc ->
          maybe_add_dependent_point(
            definitions_by_output_point,
            source_point_id,
            definition.point_id,
            source_acc
          )
        end)
      end)

    zero_degree_points =
      in_degree
      |> Enum.filter(fn {_point_id, degree} -> degree == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case do_topological_sort(zero_degree_points, in_degree, dependent_points_by_source, []) do
      {:ok, ordered_point_ids} ->
        {:ok, Enum.map(ordered_point_ids, &Map.fetch!(definitions_by_output_point, &1))}

      {:error, cycle_points} ->
        {:error, {:derived_dependency_cycle, cycle_points}}
    end
  end

  defp reduce_emitted_definition_sample(
         %Definition{} = definition,
         telemetry_sample,
         telemetry_source_sample,
         current_latest_by_point,
         emitted_samples_rev
       ) do
    case source_samples_for_definition(
           current_latest_by_point,
           telemetry_source_sample.scope_id,
           definition.source_point_ids
         ) do
      :missing ->
        {:cont, {:ok, {current_latest_by_point, emitted_samples_rev}}}

      {:ok, source_samples} ->
        emit_definition_sample(
          definition,
          telemetry_sample,
          source_samples,
          current_latest_by_point,
          emitted_samples_rev
        )
    end
  end

  defp emit_definition_sample(
         %Definition{} = definition,
         telemetry_sample,
         source_samples,
         current_latest_by_point,
         emitted_samples_rev
       ) do
    bindings =
      Map.new(source_samples, fn source_sample ->
        {source_sample.point_id, source_sample.value}
      end)

    case ExpressionEvaluator.evaluate(definition.expression, bindings) do
      {:ok, value} ->
        derived_sample =
          build_derived_sample(definition, telemetry_sample, source_samples, value)

        updated_latest_by_point =
          put_latest_source_sample(
            current_latest_by_point,
            derived_source_sample(derived_sample)
          )

        {:cont, {:ok, {updated_latest_by_point, [derived_sample | emitted_samples_rev]}}}

      {:error, reason} ->
        {:halt,
         {:error,
          {:derived_evaluation_failed, definition.derived_definition_id,
           telemetry_sample.sample_id, reason}}}
    end
  end

  defp maybe_add_dependent_point(
         definitions_by_output_point,
         source_point_id,
         dependent_point_id,
         source_acc
       ) do
    if Map.has_key?(definitions_by_output_point, source_point_id) do
      Map.update(source_acc, source_point_id, [dependent_point_id], &[dependent_point_id | &1])
    else
      source_acc
    end
  end

  defp do_topological_sort([], in_degree, _dependent_points_by_source, ordered_point_ids_rev) do
    if length(ordered_point_ids_rev) == map_size(in_degree) do
      {:ok, Enum.reverse(ordered_point_ids_rev)}
    else
      processed_points = MapSet.new(ordered_point_ids_rev)

      cycle_points =
        in_degree
        |> Map.keys()
        |> Enum.reject(&MapSet.member?(processed_points, &1))
        |> Enum.sort()

      {:error, cycle_points}
    end
  end

  defp do_topological_sort(
         [point_id | rest],
         in_degree,
         dependent_points_by_source,
         ordered_point_ids_rev
       ) do
    {updated_in_degree, released_points_rev} =
      dependent_points_by_source
      |> Map.get(point_id, [])
      |> Enum.sort()
      |> Enum.reduce({in_degree, []}, fn dependent_point_id, {degrees, released_points_rev} ->
        next_degree = Map.fetch!(degrees, dependent_point_id) - 1
        degrees = Map.put(degrees, dependent_point_id, next_degree)

        if next_degree == 0 do
          {degrees, [dependent_point_id | released_points_rev]}
        else
          {degrees, released_points_rev}
        end
      end)

    do_topological_sort(
      Enum.sort(rest ++ released_points_rev),
      updated_in_degree,
      dependent_points_by_source,
      [point_id | ordered_point_ids_rev]
    )
  end

  defp build_definitions_by_source(ordered_definitions) do
    ordered_definitions
    |> Enum.reduce(%{}, fn %Definition{} = definition, acc ->
      Enum.reduce(definition.source_point_ids, acc, fn source_point_id, source_acc ->
        Map.update(source_acc, source_point_id, [definition], &[definition | &1])
      end)
    end)
    |> Map.new(fn {source_point_id, definitions} ->
      {source_point_id, Enum.reverse(definitions)}
    end)
  end

  defp impacted_definitions(source_point_id, definitions_by_source, definition_index) do
    source_point_id
    |> collect_impacted_definitions(definitions_by_source, MapSet.new(), [])
    |> Enum.sort_by(fn %Definition{} = definition ->
      Map.fetch!(definition_index, definition.point_id)
    end)
  end

  defp collect_impacted_definitions([], _definitions_by_source, _visited_points, acc), do: acc

  defp collect_impacted_definitions(
         [source_point_id | rest],
         definitions_by_source,
         visited_points,
         acc
       ) do
    {next_queue, next_visited_points, next_acc} =
      Enum.reduce(
        Map.get(definitions_by_source, source_point_id, []),
        {rest, visited_points, acc},
        fn %Definition{} = definition, {queue, seen_points, defs} ->
          if MapSet.member?(seen_points, definition.point_id) do
            {queue, seen_points, defs}
          else
            {queue ++ [definition.point_id], MapSet.put(seen_points, definition.point_id),
             [definition | defs]}
          end
        end
      )

    collect_impacted_definitions(
      next_queue,
      definitions_by_source,
      next_visited_points,
      next_acc
    )
  end

  defp collect_impacted_definitions(source_point_id, definitions_by_source, visited_points, acc) do
    collect_impacted_definitions([source_point_id], definitions_by_source, visited_points, acc)
  end

  defp telemetry_source_sample(%TelemetrySample{} = telemetry_sample) do
    %{
      scope_id: telemetry_sample.spacecraft_id || @mission_scope_key,
      sample_id: telemetry_sample.sample_id,
      trigger_sample_id: telemetry_sample.sample_id,
      mission_id: telemetry_sample.mission_id,
      spacecraft_id: telemetry_sample.spacecraft_id,
      point_id: telemetry_sample.point_id,
      point_name: telemetry_sample.point_name,
      value: telemetry_sample.engineering_value,
      quality_state: telemetry_sample.quality_state,
      generation_time: telemetry_sample.generation_time,
      receipt_time: telemetry_sample.receipt_time,
      provenance: telemetry_sample.provenance
    }
  end

  defp derived_source_sample(%Sample{} = derived_sample) do
    %{
      scope_id: derived_sample.spacecraft_id || @mission_scope_key,
      sample_id: derived_sample.derived_sample_id,
      trigger_sample_id: derived_sample.trigger_sample_id,
      mission_id: derived_sample.mission_id,
      spacecraft_id: derived_sample.spacecraft_id,
      point_id: derived_sample.point_id,
      point_name: derived_sample.point_name,
      value: derived_sample.value,
      quality_state: derived_sample.quality_state,
      generation_time: derived_sample.generation_time,
      receipt_time: derived_sample.receipt_time,
      provenance: derived_sample.provenance
    }
  end

  defp put_latest_source_sample(latest_by_point, source_sample) do
    Map.put(latest_by_point, {source_sample.scope_id, source_sample.point_id}, source_sample)
  end

  defp persist_latest_values(repo, derived_samples) do
    Store.persist_latest_values(repo, derived_samples)
  end

  defp later_datetime(left, right) do
    case DateTime.compare(left, right) do
      :lt -> right
      :eq -> right
      :gt -> left
    end
  end

  defp quality_rank(:good), do: 0
  defp quality_rank(:suspect), do: 1
  defp quality_rank(:bad), do: 2
end
