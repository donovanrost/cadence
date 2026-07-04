defmodule Cadence.Projections.DerivedTelemetryLatestValues do
  @moduledoc """
  Rebuilds the latest derived telemetry value projection from canonical
  derived telemetry samples.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.DerivedTelemetry.Sample
  alias Cadence.Jobs

  alias Cadence.Persistence.Schemas.{
    DerivedTelemetryLatestValueRebuildRunRow,
    DerivedTelemetryLatestValueRow,
    DerivedTelemetrySampleRow
  }

  alias Cadence.Projections.DerivedTelemetryLatestValues.Run
  alias Cadence.Repo
  alias Cadence.Telemetry.LatestProjectionOrder

  @spec rebuild(binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts)

    with {:ok, persisted_run} <- insert_run(run),
         {:ok, completed_run} <- execute_rebuild(persisted_run, opts) do
      {:ok, completed_run.rebuilt_value_count}
    end
  end

  @spec start_rebuild(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def start_rebuild(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts)

    with {:ok, %Run{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :derived_telemetry_latest_value_rebuild,
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
    case Repo.get(DerivedTelemetryLatestValueRebuildRunRow, rebuild_run_id) do
      nil ->
        {:error, :derived_rebuild_run_not_found}

      %DerivedTelemetryLatestValueRebuildRunRow{} = rebuild_run_row ->
        {:ok, DerivedTelemetryLatestValueRebuildRunRow.to_domain(rebuild_run_row)}
    end
  end

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def execute_enqueued_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    with {:ok, %Run{} = run} <- fetch_run(rebuild_run_id) do
      execute_rebuild(run, opts_from_run(run))
    end
  end

  defp build_run(mission_id, opts) do
    Run.new(%{
      mission_id: mission_id,
      metadata: %{"spacecraft_id" => Keyword.get(opts, :spacecraft_id)}
    })
  end

  defp execute_rebuild(%Run{} = run, opts) do
    mission_id = run.mission_id
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    sample_rows =
      DerivedTelemetrySampleRow
      |> where([sample_row], sample_row.mission_id == ^mission_id)
      |> maybe_filter_spacecraft(spacecraft_id)
      |> Repo.all()

    latest_samples =
      sample_rows
      |> Enum.reduce(%{}, fn %DerivedTelemetrySampleRow{} = sample_row, acc ->
        key =
          {sample_row.mission_id, sample_row.spacecraft_id || "__mission__", sample_row.point_id}

        Map.update(acc, key, sample_row, &latest_sample_row(sample_row, &1))
      end)
      |> Map.values()
      |> Enum.map(&DerivedTelemetrySampleRow.to_domain/1)

    Repo.transaction(fn ->
      DerivedTelemetryLatestValueRow
      |> where([latest_value_row], latest_value_row.mission_id == ^mission_id)
      |> maybe_filter_latest_spacecraft(spacecraft_id)
      |> Repo.delete_all()

      Enum.each(latest_samples, fn %Sample{} = sample ->
        %DerivedTelemetryLatestValueRow{}
        |> DerivedTelemetryLatestValueRow.changeset(sample)
        |> Repo.insert!()
      end)
    end)
    |> case do
      {:ok, _result} ->
        completed_run =
          %Run{
            run
            | status: :completed,
              rebuilt_value_count: length(latest_samples),
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
  rescue
    exception ->
      failed_run =
        %Run{
          run
          | status: :failed,
            failure_reason: {:exception, Exception.message(exception)},
            completed_at: DateTime.utc_now()
        }

      _ = update_run(failed_run)
      {:error, {:exception, exception}}
  catch
    kind, reason ->
      failed_run =
        %Run{
          run
          | status: :failed,
            failure_reason: {kind, reason},
            completed_at: DateTime.utc_now()
        }

      _ = update_run(failed_run)
      {:error, {kind, reason}}
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id) do
    where(query, [sample_row], sample_row.spacecraft_id == ^spacecraft_id)
  end

  defp maybe_filter_latest_spacecraft(query, nil), do: query

  defp maybe_filter_latest_spacecraft(query, spacecraft_id) do
    where(query, [latest_value_row], latest_value_row.spacecraft_scope_id == ^spacecraft_id)
  end

  defp latest_sample_row(
         %DerivedTelemetrySampleRow{} = sample_row,
         %DerivedTelemetrySampleRow{} = existing_row
       ) do
    if sample_row_newer?(sample_row, existing_row), do: sample_row, else: existing_row
  end

  defp sample_row_newer?(
         %DerivedTelemetrySampleRow{} = sample_row,
         %DerivedTelemetrySampleRow{} = existing_row
       ) do
    LatestProjectionOrder.newer?(sample_row, existing_row, :derived_sample_id)
  end

  defp opts_from_run(%Run{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "spacecraft_id", Map.get(metadata, :spacecraft_id)) do
      nil -> []
      spacecraft_id -> [spacecraft_id: spacecraft_id]
    end
  end

  defp insert_run(%Run{} = run) do
    case Repo.insert(DerivedTelemetryLatestValueRebuildRunRow.changeset(run)) do
      {:ok, %DerivedTelemetryLatestValueRebuildRunRow{} = rebuild_run_row} ->
        {:ok, DerivedTelemetryLatestValueRebuildRunRow.to_domain(rebuild_run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case Repo.get(DerivedTelemetryLatestValueRebuildRunRow, run.rebuild_run_id) do
      nil ->
        {:error, :derived_rebuild_run_not_found}

      %DerivedTelemetryLatestValueRebuildRunRow{} = rebuild_run_row ->
        case Repo.update(DerivedTelemetryLatestValueRebuildRunRow.changeset(rebuild_run_row, run)) do
          {:ok, %DerivedTelemetryLatestValueRebuildRunRow{} = updated_row} ->
            {:ok, DerivedTelemetryLatestValueRebuildRunRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
