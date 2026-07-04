defmodule Cadence.Limits do
  @moduledoc """
  Evaluates governed limits over canonical telemetry and derived telemetry
  samples.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Governance
  alias Cadence.Jobs
  alias Cadence.Limits.{Definition, DefinitionLifecycle, Evaluator, Event, Run}
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Telemetry.LatestProjectionOrder

  alias Cadence.Persistence.Schemas.{
    DerivedTelemetrySampleRow,
    TelemetryLatestLimitStateRow,
    TelemetryLimitEvaluationRunRow,
    TelemetryLimitEventRow,
    TelemetrySampleRow
  }

  alias Cadence.Repo

  @mission_scope_key "__mission__"
  @type evaluation_mode :: :canonical_event | :latest_value_projection

  @spec evaluate(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def evaluate(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts)

    with {:ok, persisted_run} <- insert_run(run) do
      execute_run(persisted_run, opts)
    end
  end

  @spec start_evaluate(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def start_evaluate(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts)

    with {:ok, %Run{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :telemetry_limit_evaluation,
             mission_id,
             persisted_run.limit_run_id,
             %{"limit_run_id" => persisted_run.limit_run_id}
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
  def fetch_run(limit_run_id) when is_binary(limit_run_id) do
    case Repo.get(TelemetryLimitEvaluationRunRow, limit_run_id) do
      nil ->
        {:error, :limit_run_not_found}

      %TelemetryLimitEvaluationRunRow{} = run_row ->
        {:ok, TelemetryLimitEvaluationRunRow.to_domain(run_row)}
    end
  end

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def execute_enqueued_run(limit_run_id) when is_binary(limit_run_id) do
    with {:ok, %Run{} = run} <- fetch_run(limit_run_id) do
      execute_run(run, opts_from_run(run))
    end
  end

  defp build_run(mission_id, opts) do
    Run.new(%{
      mission_id: mission_id,
      metadata: %{"spacecraft_id" => Keyword.get(opts, :spacecraft_id)}
    })
  end

  defp execute_run(%Run{} = run, opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    definitions = active_limit_definitions(run.mission_id)

    with {:ok, source_samples} <- fetch_source_samples(run.mission_id, spacecraft_id),
         {:ok, limit_events} <- evaluate_samples(source_samples, definitions) do
      completed_run =
        %Run{
          run
          | status: :completed,
            evaluated_sample_count: length(source_samples),
            emitted_event_count: length(limit_events),
            definition_count: length(definitions),
            completed_at: DateTime.utc_now()
        }

      persist_completed_run(completed_run, limit_events)
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
    telemetry_samples =
      TelemetrySampleRow
      |> where([sample_row], sample_row.mission_id == ^mission_id)
      |> maybe_filter_telemetry_spacecraft(spacecraft_id)
      |> Repo.all()
      |> Enum.map(fn %TelemetrySampleRow{} = sample_row ->
        sample = TelemetrySampleRow.to_domain(sample_row)

        %{
          source_sample_type: :telemetry_sample,
          sample_id: sample.sample_id,
          mission_id: sample.mission_id,
          spacecraft_id: sample.spacecraft_id,
          point_id: sample.point_id,
          point_name: sample.point_name,
          value: sample.engineering_value,
          generation_time: sample.generation_time,
          receipt_time: sample.receipt_time,
          provenance: sample.provenance
        }
      end)

    derived_samples =
      DerivedTelemetrySampleRow
      |> where([sample_row], sample_row.mission_id == ^mission_id)
      |> maybe_filter_derived_spacecraft(spacecraft_id)
      |> Repo.all()
      |> Enum.map(fn %DerivedTelemetrySampleRow{} = sample_row ->
        sample = DerivedTelemetrySampleRow.to_domain(sample_row)

        %{
          source_sample_type: :derived_telemetry_sample,
          sample_id: sample.derived_sample_id,
          mission_id: sample.mission_id,
          spacecraft_id: sample.spacecraft_id,
          point_id: sample.point_id,
          point_name: sample.point_name,
          value: sample.value,
          generation_time: sample.generation_time,
          receipt_time: sample.receipt_time,
          provenance: sample.provenance
        }
      end)

    merged_samples =
      (telemetry_samples ++ derived_samples)
      |> Enum.sort(fn left, right ->
        compare_source_sample_order(left, right) != :gt
      end)

    {:ok, merged_samples}
  end

  defp evaluate_samples(source_samples, definitions) do
    evaluate_source_samples(source_samples, definitions)
  end

  @doc false
  @spec evaluate_source_samples([map()], [Definition.t()], keyword()) ::
          {:ok, [Event.t()]} | {:error, term()}
  def evaluate_source_samples(source_samples, definitions, opts \\ [])
      when is_list(source_samples) and is_list(definitions) and is_list(opts) do
    mode = Keyword.get(opts, :mode, :canonical_event)
    definitions_by_point = Enum.group_by(definitions, & &1.point_id)

    Enum.reduce_while(source_samples, {:ok, []}, fn source_sample, {:ok, acc} ->
      relevant_definitions = Map.get(definitions_by_point, source_sample.point_id, [])

      case build_events_for_sample(source_sample, relevant_definitions, mode) do
        {:ok, events} -> {:cont, {:ok, Enum.reverse(events) ++ acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, limit_events} -> {:ok, Enum.reverse(limit_events)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_events_for_sample(_source_sample, [], _mode), do: {:ok, []}

  defp build_events_for_sample(source_sample, definitions, mode) do
    Enum.reduce_while(definitions, {:ok, []}, fn %Definition{} = definition, {:ok, acc} ->
      limit_state = Evaluator.evaluate(source_sample.value, definition.thresholds)

      event =
        %Event{
          limit_event_id: build_limit_event_id(definition, source_sample, mode),
          mission_id: source_sample.mission_id,
          spacecraft_id: source_sample.spacecraft_id,
          point_id: source_sample.point_id,
          point_name: source_sample.point_name,
          source_sample_type: source_sample.source_sample_type,
          sample_id: source_sample.sample_id,
          limit_definition_id: definition.limit_definition_id,
          limit_definition_version: definition.version,
          limit_set_name: definition.limit_set_name,
          evaluated_value: source_sample.value,
          limit_state: limit_state,
          normalized_state: Evaluator.normalize_state(limit_state),
          violation: Evaluator.violation?(limit_state),
          generation_time: source_sample.generation_time,
          receipt_time: source_sample.receipt_time,
          provenance: build_event_provenance(source_sample, definition, mode)
        }

      {:cont, {:ok, [event | acc]}}
    end)
  end

  defp persist_completed_run(%Run{} = run, limit_events) do
    projected_events = MissionEventProjection.project_many(limit_events)

    Multi.new()
    |> Multi.run(:limit_run, fn repo, _changes ->
      repo_run_update(repo, run)
    end)
    |> add_event_inserts(limit_events)
    |> Multi.run(:mission_events, fn repo, _changes ->
      MissionEventProjection.persist_entries(repo, projected_events)
    end)
    |> Multi.run(:latest_limit_states, fn repo, _changes ->
      persist_latest_states(repo, limit_events)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> {:ok, run}
      {:error, _operation, %Changeset{} = changeset, _changes_so_far} -> {:error, changeset}
      {:error, _operation, reason, _changes_so_far} -> {:error, reason}
    end
  end

  defp add_event_inserts(%Multi{} = multi, limit_events) do
    Enum.reduce(limit_events, multi, fn %Event{} = event, acc ->
      Multi.insert(
        acc,
        {:limit_event, event.limit_event_id},
        TelemetryLimitEventRow.changeset(event),
        on_conflict: :nothing,
        conflict_target: [:limit_event_id]
      )
    end)
  end

  defp persist_latest_states(repo, limit_events) do
    Enum.reduce_while(limit_events, {:ok, []}, fn %Event{} = event, {:ok, acc} ->
      case persist_latest_state(repo, event) do
        {:ok, latest_state_row} -> {:cont, {:ok, [latest_state_row | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_latest_state(repo, %Event{} = event) do
    existing_row =
      repo.get_by(TelemetryLatestLimitStateRow,
        mission_id: event.mission_id,
        spacecraft_scope_id: event.spacecraft_id || @mission_scope_key,
        point_id: event.point_id
      )

    cond do
      is_nil(existing_row) ->
        %TelemetryLatestLimitStateRow{}
        |> TelemetryLatestLimitStateRow.changeset(event)
        |> repo.insert()

      latest_state_newer?(event, existing_row) ->
        existing_row
        |> TelemetryLatestLimitStateRow.changeset(event)
        |> repo.update()

      true ->
        {:ok, existing_row}
    end
  end

  defp latest_state_newer?(%Event{} = event, %TelemetryLatestLimitStateRow{} = latest_state_row) do
    LatestProjectionOrder.newer?(event, latest_state_row, :limit_event_id)
  end

  defp compare_source_sample_order(left, right) do
    compare_source_sample_keys(source_sample_order_key(left), source_sample_order_key(right))
  end

  defp source_sample_order_key(sample) do
    {sample.receipt_time, sample.generation_time || sample.receipt_time, sample.sample_id}
  end

  defp compare_source_sample_keys(
         {receipt_a, generation_a, id_a},
         {receipt_b, generation_b, id_b}
       ) do
    case DateTime.compare(receipt_a, receipt_b) do
      :eq ->
        case DateTime.compare(generation_a, generation_b) do
          :eq -> compare_source_sample_ids(id_a, id_b)
          other -> other
        end

      other ->
        other
    end
  end

  defp compare_source_sample_ids(left, right) when left > right, do: :gt
  defp compare_source_sample_ids(left, right) when left < right, do: :lt
  defp compare_source_sample_ids(_left, _right), do: :eq

  defp build_limit_event_id(definition, source_sample, :canonical_event) do
    "limit_event:" <>
      definition.limit_definition_id <>
      ":v" <>
      Integer.to_string(definition.version) <>
      ":" <>
      Atom.to_string(source_sample.source_sample_type) <>
      ":" <> source_sample.sample_id
  end

  defp build_limit_event_id(definition, source_sample, :latest_value_projection) do
    "limit_state_snapshot:" <>
      definition.limit_definition_id <>
      ":v" <>
      Integer.to_string(definition.version) <>
      ":" <>
      Atom.to_string(source_sample.source_sample_type) <>
      ":" <> source_sample.sample_id
  end

  defp build_event_provenance(source_sample, definition, mode) do
    source_sample.provenance
    |> Map.merge(%{
      "limit_definition_id" => definition.limit_definition_id,
      "limit_definition_version" => definition.version
    })
    |> maybe_put_lifecycle_metadata(definition)
    |> maybe_put_evaluation_mode(mode)
  end

  defp maybe_put_lifecycle_metadata(provenance, %Definition{metadata: metadata})
       when is_map(metadata) do
    provenance
    |> maybe_put_metadata(metadata, "definition_activation_key")
    |> maybe_put_metadata(metadata, "limit_definition_lifecycle_event_id")
    |> maybe_put_metadata(metadata, "limit_activation_event_id")
    |> maybe_put_metadata(metadata, "limit_activation_event_type")
    |> maybe_put_metadata(metadata, "active_from")
  end

  defp maybe_put_lifecycle_metadata(provenance, %Definition{}), do: provenance

  defp maybe_put_metadata(provenance, metadata, key) do
    case Map.get(metadata, key) do
      nil -> provenance
      value -> Map.put(provenance, key, value)
    end
  end

  defp maybe_put_evaluation_mode(provenance, :latest_value_projection) do
    Map.put(provenance, "evaluation_mode", "latest_value_projection")
  end

  defp maybe_put_evaluation_mode(provenance, _mode), do: provenance

  defp active_limit_definitions(mission_id) do
    case DefinitionLifecycle.list_active_definitions(mission_id) do
      [] -> Governance.list_limit_definitions(mission_id)
      definitions -> definitions
    end
  end

  defp insert_run(%Run{} = run) do
    case Repo.insert(TelemetryLimitEvaluationRunRow.changeset(run)) do
      {:ok, %TelemetryLimitEvaluationRunRow{} = run_row} ->
        {:ok, TelemetryLimitEvaluationRunRow.to_domain(run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case repo_run_update(Repo, run) do
      {:ok, %TelemetryLimitEvaluationRunRow{} = run_row} ->
        {:ok, TelemetryLimitEvaluationRunRow.to_domain(run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp repo_run_update(repo, %Run{} = run) do
    case repo.get(TelemetryLimitEvaluationRunRow, run.limit_run_id) do
      nil ->
        {:error, :limit_run_not_found}

      %TelemetryLimitEvaluationRunRow{} = run_row ->
        repo.update(TelemetryLimitEvaluationRunRow.changeset(run_row, run))
    end
  end

  defp opts_from_run(%Run{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "spacecraft_id", Map.get(metadata, :spacecraft_id)) do
      nil -> []
      spacecraft_id -> [spacecraft_id: spacecraft_id]
    end
  end

  defp maybe_filter_telemetry_spacecraft(query, nil), do: query

  defp maybe_filter_telemetry_spacecraft(query, spacecraft_id),
    do: where(query, [sample_row], sample_row.spacecraft_id == ^spacecraft_id)

  defp maybe_filter_derived_spacecraft(query, nil), do: query

  defp maybe_filter_derived_spacecraft(query, spacecraft_id),
    do: where(query, [sample_row], sample_row.spacecraft_id == ^spacecraft_id)
end
