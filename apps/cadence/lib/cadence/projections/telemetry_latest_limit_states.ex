# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Projections.TelemetryLatestLimitStates do
  @moduledoc """
  Rebuilds the latest telemetry limit-state projection from canonical limit
  events.
  """

  alias Ecto.Changeset

  alias Cadence.Jobs
  alias Cadence.Limits
  alias Cadence.Limits.Event
  alias Cadence.Limits.Store

  alias Cadence.DerivedTelemetry.Store, as: DerivedTelemetryStore

  alias Cadence.Projections.TelemetryLatestLimitStates.{RebuildRunRow, Run}
  alias Cadence.Repo
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.LatestProjectionOrder

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
    case Repo.get(RebuildRunRow, rebuild_run_id) do
      nil ->
        {:error, :limit_state_rebuild_run_not_found}

      %RebuildRunRow{} = run_row ->
        {:ok, RebuildRunRow.to_domain(run_row)}
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
      mission_id
      |> Store.list_events(spacecraft_id: spacecraft_id)
      |> Enum.reduce(%{}, fn %Event{} = event, acc ->
        key = {event.mission_id, event.spacecraft_id || "__mission__", event.point_id}

        Map.update(acc, key, event, &latest_event(&1, event))
      end)
      |> Map.values()

    Store.replace_latest_states(mission_id, latest_events, opts)
    |> case do
      :ok ->
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
    definitions = Limits.list_limit_definitions(mission_id)

    with {:ok, source_samples} <- fetch_latest_value_sources(mission_id, spacecraft_id),
         {:ok, latest_state_events} <-
           Limits.evaluate_source_samples(
             source_samples,
             definitions,
             mode: :latest_value_projection
           ) do
      Store.replace_latest_states(mission_id, latest_state_events, opts)
      |> case do
        :ok ->
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
    case Repo.insert(RebuildRunRow.changeset(run)) do
      {:ok, %RebuildRunRow{} = run_row} ->
        {:ok, RebuildRunRow.to_domain(run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case Repo.get(RebuildRunRow, run.rebuild_run_id) do
      nil ->
        {:error, :limit_state_rebuild_run_not_found}

      %RebuildRunRow{} = run_row ->
        case Repo.update(RebuildRunRow.changeset(run_row, run)) do
          {:ok, %RebuildRunRow{} = updated_row} ->
            {:ok, RebuildRunRow.to_domain(updated_row)}

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

  defp latest_event(%Event{} = existing, %Event{} = candidate) do
    if LatestProjectionOrder.newer?(candidate, existing, :limit_event_id),
      do: candidate,
      else: existing
  end

  defp fetch_latest_value_sources(mission_id, spacecraft_id) do
    telemetry_opts = if spacecraft_id, do: [spacecraft_id: spacecraft_id], else: []

    telemetry_sources =
      mission_id
      |> CurrentValueStore.latest_values_for_mission(telemetry_opts)
      |> Enum.map(fn latest_value ->
        %{
          source_sample_type: :telemetry_sample,
          sample_id: latest_value.sample_id,
          mission_id: latest_value.mission_id,
          spacecraft_id: latest_value.spacecraft_id,
          point_id: latest_value.point_id,
          point_name: latest_value.point_name,
          value: unwrap_value(latest_value.engineering_value, latest_value.raw_value),
          generation_time: latest_value.generation_time,
          receipt_time: latest_value.receipt_time,
          provenance: latest_value.provenance
        }
      end)

    derived_sources =
      mission_id
      |> DerivedTelemetryStore.list_latest_values(telemetry_opts)
      |> Enum.map(fn latest_value ->
        %{
          source_sample_type: :derived_telemetry_sample,
          sample_id: latest_value.derived_sample_id,
          mission_id: latest_value.mission_id,
          spacecraft_id: latest_value.spacecraft_id,
          point_id: latest_value.point_id,
          point_name: latest_value.point_name,
          value: latest_value.value,
          generation_time: latest_value.generation_time,
          receipt_time: latest_value.receipt_time,
          provenance: latest_value.provenance
        }
      end)

    merged_sources =
      (telemetry_sources ++ derived_sources)
      |> Enum.sort(fn left, right ->
        LatestProjectionOrder.compare(left, right, :sample_id) != :gt
      end)

    {:ok, merged_sources}
  end

  defp unwrap_value(%{"value" => value}, _fallback), do: value
  defp unwrap_value(nil, %{"value" => value}), do: value
  defp unwrap_value(nil, fallback), do: fallback
  defp unwrap_value(value, _fallback), do: value

  defp source_mode_name(:canonical_limit_events), do: "canonical_limit_events"
  defp source_mode_name(:latest_value_projection), do: "latest_value_projection"
end
