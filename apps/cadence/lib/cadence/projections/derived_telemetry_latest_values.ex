defmodule Cadence.Projections.DerivedTelemetryLatestValues do
  @moduledoc """
  Rebuilds the latest derived telemetry value projection from canonical
  derived telemetry samples.
  """

  alias Ecto.Changeset

  alias Cadence.DerivedTelemetry.Sample
  alias Cadence.DerivedTelemetry.Store
  alias Cadence.Jobs

  alias Cadence.Projections.DerivedTelemetryLatestValues.{RebuildRunRow, Run}
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
    case Repo.get(RebuildRunRow, rebuild_run_id) do
      nil ->
        {:error, :derived_rebuild_run_not_found}

      %RebuildRunRow{} = rebuild_run_row ->
        {:ok, RebuildRunRow.to_domain(rebuild_run_row)}
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

    samples = Store.list_samples(mission_id, spacecraft_id: spacecraft_id)

    latest_samples =
      samples
      |> Enum.reduce(%{}, fn %Sample{} = sample, acc ->
        key =
          {sample.mission_id, sample.spacecraft_id || "__mission__", sample.point_id}

        Map.update(acc, key, sample, &latest_sample(&1, sample))
      end)
      |> Map.values()

    Store.replace_latest_values(mission_id, latest_samples, opts)
    |> case do
      :ok ->
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

  defp latest_sample(%Sample{} = existing, %Sample{} = candidate) do
    if LatestProjectionOrder.newer?(candidate, existing, :derived_sample_id),
      do: candidate,
      else: existing
  end

  defp opts_from_run(%Run{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "spacecraft_id", Map.get(metadata, :spacecraft_id)) do
      nil -> []
      spacecraft_id -> [spacecraft_id: spacecraft_id]
    end
  end

  defp insert_run(%Run{} = run) do
    case Repo.insert(RebuildRunRow.changeset(run)) do
      {:ok, %RebuildRunRow{} = rebuild_run_row} ->
        {:ok, RebuildRunRow.to_domain(rebuild_run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case Repo.get(RebuildRunRow, run.rebuild_run_id) do
      nil ->
        {:error, :derived_rebuild_run_not_found}

      %RebuildRunRow{} = rebuild_run_row ->
        case Repo.update(RebuildRunRow.changeset(rebuild_run_row, run)) do
          {:ok, %RebuildRunRow{} = updated_row} ->
            {:ok, RebuildRunRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
