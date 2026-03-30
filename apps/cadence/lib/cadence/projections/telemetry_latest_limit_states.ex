defmodule Cadence.Projections.TelemetryLatestLimitStates do
  @moduledoc """
  Rebuilds the latest telemetry limit-state projection from canonical limit
  events.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Governance
  alias Cadence.Jobs
  alias Cadence.Limits.Event
  alias Cadence.Limits

  alias Cadence.Persistence.Schemas.{
    DerivedTelemetryLatestValueRow,
    TelemetryLatestLimitStateRebuildRunRow,
    TelemetryLatestLimitStateRow,
    TelemetryLatestValueRow,
    TelemetryLimitEventRow
  }

  alias Cadence.Projections.TelemetryLatestLimitStates.Run
  alias Cadence.Repo

  @spec rebuild(binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts, :canonical_limit_events)

    with {:ok, persisted_run} <- insert_run(run),
         {:ok, completed_run} <- execute_rebuild(persisted_run, opts) do
      {:ok, completed_run.rebuilt_state_count}
    end
  end

  @spec refresh_from_latest_values(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def refresh_from_latest_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts, :latest_value_projection)

    with {:ok, persisted_run} <- insert_run(run),
         {:ok, completed_run} <- execute_refresh_from_latest_values(persisted_run, opts) do
      {:ok, completed_run.rebuilt_state_count}
    end
  end

  @spec start_rebuild(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def start_rebuild(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts, :canonical_limit_events)

    with {:ok, %Run{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :telemetry_latest_limit_state_rebuild,
             mission_id,
             persisted_run.rebuild_run_id,
             %{"rebuild_run_id" => persisted_run.rebuild_run_id}
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

  @spec start_refresh_from_latest_values(binary(), keyword()) ::
          {:ok, Run.t()} | {:error, term()}
  def start_refresh_from_latest_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts, :latest_value_projection)

    with {:ok, %Run{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :telemetry_latest_limit_state_refresh,
             mission_id,
             persisted_run.rebuild_run_id,
             %{"rebuild_run_id" => persisted_run.rebuild_run_id}
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
  def fetch_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    case Repo.get(TelemetryLatestLimitStateRebuildRunRow, rebuild_run_id) do
      nil ->
        {:error, :limit_state_rebuild_run_not_found}

      %TelemetryLatestLimitStateRebuildRunRow{} = run_row ->
        {:ok, TelemetryLatestLimitStateRebuildRunRow.to_domain(run_row)}
    end
  end

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def execute_enqueued_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    with {:ok, %Run{} = run} <- fetch_run(rebuild_run_id) do
      execute_rebuild(run, opts_from_run(run))
    end
  end

  @doc false
  @spec execute_enqueued_refresh_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def execute_enqueued_refresh_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    with {:ok, %Run{} = run} <- fetch_run(rebuild_run_id) do
      execute_refresh_from_latest_values(run, opts_from_run(run))
    end
  end

  defp build_run(mission_id, opts, source_mode) do
    Run.new(%{
      mission_id: mission_id,
      metadata: %{
        "spacecraft_id" => Keyword.get(opts, :spacecraft_id),
        "source_mode" => source_mode_name(source_mode)
      }
    })
  end

  defp execute_rebuild(%Run{} = run, opts) do
    mission_id = run.mission_id
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    latest_events =
      TelemetryLimitEventRow
      |> where([event_row], event_row.mission_id == ^mission_id)
      |> maybe_filter_spacecraft(spacecraft_id)
      |> Repo.all()
      |> Enum.reduce(%{}, fn %TelemetryLimitEventRow{} = event_row, acc ->
        key = {event_row.mission_id, event_row.spacecraft_id || "__mission__", event_row.point_id}

        case Map.fetch(acc, key) do
          :error ->
            Map.put(acc, key, event_row)

          {:ok, %TelemetryLimitEventRow{} = existing_row} ->
            if event_row_newer?(event_row, existing_row) do
              Map.put(acc, key, event_row)
            else
              acc
            end
        end
      end)
      |> Map.values()
      |> Enum.map(&TelemetryLimitEventRow.to_domain/1)

    Repo.transaction(fn ->
      TelemetryLatestLimitStateRow
      |> where([state_row], state_row.mission_id == ^mission_id)
      |> maybe_filter_latest_spacecraft(spacecraft_id)
      |> Repo.delete_all()

      Enum.each(latest_events, fn %Event{} = event ->
        %TelemetryLatestLimitStateRow{}
        |> TelemetryLatestLimitStateRow.changeset(event)
        |> Repo.insert!()
      end)
    end)
    |> case do
      {:ok, _result} ->
        completed_run =
          %Run{
            run
            | status: :completed,
              rebuilt_state_count: length(latest_events),
              completed_at: DateTime.utc_now()
          }

        update_run(completed_run)

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

  defp execute_refresh_from_latest_values(%Run{} = run, opts) do
    mission_id = run.mission_id
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    definitions = Governance.list_limit_definitions(mission_id)

    with {:ok, source_samples} <- fetch_latest_value_sources(mission_id, spacecraft_id),
         {:ok, latest_state_events} <-
           Limits.evaluate_source_samples(
             source_samples,
             definitions,
             mode: :latest_value_projection
           ) do
      Repo.transaction(fn ->
        TelemetryLatestLimitStateRow
        |> where([state_row], state_row.mission_id == ^mission_id)
        |> maybe_filter_latest_spacecraft(spacecraft_id)
        |> Repo.delete_all()

        Enum.each(latest_state_events, fn %Event{} = event ->
          %TelemetryLatestLimitStateRow{}
          |> TelemetryLatestLimitStateRow.changeset(event)
          |> Repo.insert!()
        end)
      end)
      |> case do
        {:ok, _result} ->
          completed_run =
            %Run{
              run
              | status: :completed,
                rebuilt_state_count: length(latest_state_events),
                completed_at: DateTime.utc_now()
            }

          update_run(completed_run)

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
  end

  defp insert_run(%Run{} = run) do
    case Repo.insert(TelemetryLatestLimitStateRebuildRunRow.changeset(run)) do
      {:ok, %TelemetryLatestLimitStateRebuildRunRow{} = run_row} ->
        {:ok, TelemetryLatestLimitStateRebuildRunRow.to_domain(run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case Repo.get(TelemetryLatestLimitStateRebuildRunRow, run.rebuild_run_id) do
      nil ->
        {:error, :limit_state_rebuild_run_not_found}

      %TelemetryLatestLimitStateRebuildRunRow{} = run_row ->
        case Repo.update(TelemetryLatestLimitStateRebuildRunRow.changeset(run_row, run)) do
          {:ok, %TelemetryLatestLimitStateRebuildRunRow{} = updated_row} ->
            {:ok, TelemetryLatestLimitStateRebuildRunRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp opts_from_run(%Run{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "spacecraft_id", Map.get(metadata, :spacecraft_id)) do
      nil -> []
      spacecraft_id -> [spacecraft_id: spacecraft_id]
    end
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id),
    do: where(query, [event_row], event_row.spacecraft_id == ^spacecraft_id)

  defp maybe_filter_latest_spacecraft(query, nil), do: query

  defp maybe_filter_latest_spacecraft(query, spacecraft_id),
    do: where(query, [state_row], state_row.spacecraft_scope_id == ^spacecraft_id)

  defp event_row_newer?(event_row, existing_row) do
    compare_sort_keys(
      {event_row.generation_time || event_row.receipt_time, event_row.receipt_time,
       event_row.limit_event_id},
      {existing_row.generation_time || existing_row.receipt_time, existing_row.receipt_time,
       existing_row.limit_event_id}
    ) == :gt
  end

  defp compare_sort_keys({time_a, receipt_a, id_a}, {time_b, receipt_b, id_b}) do
    case DateTime.compare(time_a, time_b) do
      :eq ->
        case DateTime.compare(receipt_a, receipt_b) do
          :eq -> compare_ids(id_a, id_b)
          other -> other
        end

      other ->
        other
    end
  end

  defp compare_ids(id_a, id_b) when id_a > id_b, do: :gt
  defp compare_ids(id_a, id_b) when id_a < id_b, do: :lt
  defp compare_ids(_id_a, _id_b), do: :eq

  defp fetch_latest_value_sources(mission_id, spacecraft_id) do
    telemetry_sources =
      TelemetryLatestValueRow
      |> where([latest_value_row], latest_value_row.mission_id == ^mission_id)
      |> maybe_filter_latest_telemetry_spacecraft(spacecraft_id)
      |> Repo.all()
      |> Enum.map(fn %TelemetryLatestValueRow{} = latest_value_row ->
        %{
          source_sample_type: :telemetry_sample,
          sample_id: latest_value_row.sample_id,
          mission_id: latest_value_row.mission_id,
          spacecraft_id: latest_value_row.spacecraft_id,
          point_id: latest_value_row.point_id,
          point_name: latest_value_row.point_name,
          value: unwrap_value(latest_value_row.engineering_value, latest_value_row.raw_value),
          generation_time: latest_value_row.generation_time,
          receipt_time: latest_value_row.receipt_time,
          provenance: latest_value_row.provenance
        }
      end)

    derived_sources =
      DerivedTelemetryLatestValueRow
      |> where([latest_value_row], latest_value_row.mission_id == ^mission_id)
      |> maybe_filter_latest_derived_spacecraft(spacecraft_id)
      |> Repo.all()
      |> Enum.map(fn %DerivedTelemetryLatestValueRow{} = latest_value_row ->
        %{
          source_sample_type: :derived_telemetry_sample,
          sample_id: latest_value_row.derived_sample_id,
          mission_id: latest_value_row.mission_id,
          spacecraft_id: latest_value_row.spacecraft_id,
          point_id: latest_value_row.point_id,
          point_name: latest_value_row.point_name,
          value: unwrap_value(latest_value_row.value),
          generation_time: latest_value_row.generation_time,
          receipt_time: latest_value_row.receipt_time,
          provenance: latest_value_row.provenance
        }
      end)

    merged_sources =
      (telemetry_sources ++ derived_sources)
      |> Enum.sort(fn left, right ->
        compare_sort_keys(
          latest_value_source_sort_key(left),
          latest_value_source_sort_key(right)
        ) != :gt
      end)

    {:ok, merged_sources}
  end

  defp unwrap_value(%{"value" => value}, _fallback), do: value
  defp unwrap_value(nil, %{"value" => value}), do: value
  defp unwrap_value(nil, fallback), do: fallback
  defp unwrap_value(value, _fallback), do: value

  defp unwrap_value(%{"value" => value}), do: value
  defp unwrap_value(value), do: value

  defp latest_value_source_sort_key(source_sample) do
    {source_sample.generation_time || source_sample.receipt_time, source_sample.receipt_time,
     source_sample.sample_id}
  end

  defp maybe_filter_latest_telemetry_spacecraft(query, nil), do: query

  defp maybe_filter_latest_telemetry_spacecraft(query, spacecraft_id) do
    where(query, [latest_value_row], latest_value_row.spacecraft_scope_id == ^spacecraft_id)
  end

  defp maybe_filter_latest_derived_spacecraft(query, nil), do: query

  defp maybe_filter_latest_derived_spacecraft(query, spacecraft_id) do
    where(query, [latest_value_row], latest_value_row.spacecraft_scope_id == ^spacecraft_id)
  end

  defp source_mode_name(:canonical_limit_events), do: "canonical_limit_events"
  defp source_mode_name(:latest_value_projection), do: "latest_value_projection"
end
