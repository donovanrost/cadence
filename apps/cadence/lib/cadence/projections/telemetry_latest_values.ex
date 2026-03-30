defmodule Cadence.Projections.TelemetryLatestValues do
  @moduledoc """
  Rebuilds the latest telemetry value projection from canonical telemetry
  samples.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Jobs

  alias Cadence.Persistence.Schemas.{
    TelemetryLatestValueRebuildRunRow,
    TelemetryLatestValueRow,
    TelemetrySampleRow
  }

  alias Cadence.Projections.TelemetryLatestValues.Run
  alias Cadence.Repo
  alias Cadence.Telemetry.Sample

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
             :telemetry_latest_value_rebuild,
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
    case Repo.get(TelemetryLatestValueRebuildRunRow, rebuild_run_id) do
      nil ->
        {:error, :rebuild_run_not_found}

      %TelemetryLatestValueRebuildRunRow{} = rebuild_run_row ->
        {:ok, TelemetryLatestValueRebuildRunRow.to_domain(rebuild_run_row)}
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
      metadata: %{
        "spacecraft_id" => Keyword.get(opts, :spacecraft_id)
      }
    })
  end

  defp execute_rebuild(%Run{} = run, opts) do
    mission_id = run.mission_id
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    sample_rows =
      TelemetrySampleRow
      |> where([sample_row], sample_row.mission_id == ^mission_id)
      |> maybe_filter_spacecraft(spacecraft_id)
      |> Repo.all()

    latest_samples =
      sample_rows
      |> Enum.reduce(%{}, fn %TelemetrySampleRow{} = sample_row, acc ->
        key =
          {sample_row.mission_id, sample_row.spacecraft_id || "__mission__", sample_row.point_id}

        case Map.fetch(acc, key) do
          :error ->
            Map.put(acc, key, sample_row)

          {:ok, %TelemetrySampleRow{} = existing_row} ->
            if sample_row_newer?(sample_row, existing_row) do
              Map.put(acc, key, sample_row)
            else
              acc
            end
        end
      end)
      |> Map.values()
      |> Enum.map(&TelemetrySampleRow.to_domain/1)

    Repo.transaction(fn ->
      TelemetryLatestValueRow
      |> where([latest_value_row], latest_value_row.mission_id == ^mission_id)
      |> maybe_filter_latest_spacecraft(spacecraft_id)
      |> Repo.delete_all()

      Enum.each(latest_samples, fn %Sample{} = sample ->
        %TelemetryLatestValueRow{}
        |> TelemetryLatestValueRow.changeset(sample)
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

  defp sample_row_newer?(%TelemetrySampleRow{} = sample_row, %TelemetrySampleRow{} = existing_row) do
    compare_sort_keys(sample_row_sort_key(sample_row), sample_row_sort_key(existing_row)) == :gt
  end

  defp sample_row_sort_key(%TelemetrySampleRow{} = sample_row) do
    {sample_row.generation_time || sample_row.receipt_time, sample_row.receipt_time,
     sample_row.sample_id}
  end

  defp compare_sort_keys({time_a, receipt_a, sample_id_a}, {time_b, receipt_b, sample_id_b}) do
    case DateTime.compare(time_a, time_b) do
      :eq ->
        case DateTime.compare(receipt_a, receipt_b) do
          :eq -> compare_ids(sample_id_a, sample_id_b)
          other -> other
        end

      other ->
        other
    end
  end

  defp compare_ids(id_a, id_b) when id_a > id_b, do: :gt
  defp compare_ids(id_a, id_b) when id_a < id_b, do: :lt
  defp compare_ids(_id_a, _id_b), do: :eq

  defp opts_from_run(%Run{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "spacecraft_id", Map.get(metadata, :spacecraft_id)) do
      nil -> []
      spacecraft_id -> [spacecraft_id: spacecraft_id]
    end
  end

  defp insert_run(%Run{} = run) do
    case Repo.insert(TelemetryLatestValueRebuildRunRow.changeset(run)) do
      {:ok, %TelemetryLatestValueRebuildRunRow{} = rebuild_run_row} ->
        {:ok, TelemetryLatestValueRebuildRunRow.to_domain(rebuild_run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case Repo.get(TelemetryLatestValueRebuildRunRow, run.rebuild_run_id) do
      nil ->
        {:error, :rebuild_run_not_found}

      %TelemetryLatestValueRebuildRunRow{} = rebuild_run_row ->
        case Repo.update(TelemetryLatestValueRebuildRunRow.changeset(rebuild_run_row, run)) do
          {:ok, %TelemetryLatestValueRebuildRunRow{} = updated_row} ->
            {:ok, TelemetryLatestValueRebuildRunRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
