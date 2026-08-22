defmodule Cadence.Projections.TelemetryLatestValues do
  @moduledoc """
  Rebuilds the latest telemetry value projection from canonical telemetry
  samples.
  """

  alias Ecto.Changeset

  alias Cadence.Jobs

  alias Cadence.Projections.TelemetryLatestValues.{RebuildRunRow, Run}
  alias Cadence.Repo
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.EffectiveSelection
  alias Cadence.Telemetry.LatestProjectionOrder
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.SampleRecords
  alias Cadence.Telemetry.SourceFilters
  alias Cadence.Telemetry.Storage.ObservationIdentityStates

  @spec rebuild(binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    run = build_run(mission_id, opts)

    with {:ok, persisted_run} <- insert_run(run),
         {:ok, completed_run} <- execute_rebuild(persisted_run, opts) do
      {:ok, completed_run.rebuilt_value_count}
    end
  end

  @spec refresh_point(binary(), binary(), keyword()) ::
          {:ok, Sample.t() | nil} | {:error, term()}
  def refresh_point(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    selected_sample =
      mission_id
      |> sample_rows_for_point(point_id, opts)
      |> latest_sample_for_rows(identity_rows_for_point(mission_id, point_id, opts), opts)

    with :ok <- CurrentValueStore.replace_value(mission_id, point_id, selected_sample, opts) do
      {:ok, selected_sample}
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
    case Repo.get(RebuildRunRow, rebuild_run_id) do
      nil ->
        {:error, :rebuild_run_not_found}

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
      metadata: %{
        "spacecraft_id" => Keyword.get(opts, :spacecraft_id),
        "realm" => Keyword.get(opts, :realm),
        "data_source_id" => Keyword.get(opts, :data_source_id),
        "source_binding_id" => SourceFilters.binding_id(opts)
      }
    })
  end

  defp execute_rebuild(%Run{} = run, opts) do
    mission_id = run.mission_id
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    samples = SampleRecords.list_samples(mission_id, spacecraft_id: spacecraft_id)

    latest_samples =
      samples
      |> latest_samples_for_samples(identity_states_for_mission(mission_id, opts), opts)

    CurrentValueStore.replace_values_for_scope(mission_id, latest_samples, opts)
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

  defp sample_rows_for_point(mission_id, point_id, opts) do
    mission_id
    |> SampleRecords.list_samples(
      point_id: point_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id)
    )
    |> maybe_filter_exact_spacecraft(opts)
  end

  defp identity_rows_for_point(mission_id, point_id, opts) do
    mission_id
    |> ObservationIdentityStates.list_for_selection(
      organization_id: Keyword.get(opts, :organization_id),
      point_id: point_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      realm: Keyword.get(opts, :realm),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      data_source_id: Keyword.get(opts, :data_source_id),
      binding_id: SourceFilters.binding_id(opts)
    )
    |> maybe_filter_exact_spacecraft(opts)
  end

  defp identity_states_for_mission(mission_id, opts) do
    ObservationIdentityStates.list_for_selection(mission_id,
      organization_id: Keyword.get(opts, :organization_id),
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      realm: Keyword.get(opts, :realm),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      data_source_id: Keyword.get(opts, :data_source_id),
      binding_id: SourceFilters.binding_id(opts)
    )
  end

  defp latest_sample_for_rows(sample_rows, identity_rows, opts) do
    sample_rows
    |> effective_selected_samples(identity_rows, opts)
    |> Enum.reduce(nil, fn
      %Sample{} = sample, nil -> sample
      %Sample{} = sample, %Sample{} = latest -> latest_sample(sample, latest)
    end)
  end

  defp latest_samples_for_samples(samples, identity_rows, opts) do
    samples
    |> effective_selected_samples(identity_rows, opts)
    |> Enum.reduce(%{}, fn %Sample{} = sample, acc ->
      {realm, data_source_id, binding_id} = SourceFilters.sample_key(sample)

      key =
        {sample.mission_id, sample.spacecraft_id || "__mission__", sample.point_id, realm,
         data_source_id, binding_id}

      Map.update(acc, key, sample, &latest_sample(sample, &1))
    end)
    |> Map.values()
  end

  defp effective_selected_samples(samples, identity_rows, opts) do
    samples
    |> SourceFilters.filter_samples(opts)
    |> EffectiveSelection.selected_samples(identity_rows, opts)
  end

  defp maybe_filter_exact_spacecraft(records, opts) do
    case Keyword.fetch(opts, :spacecraft_id) do
      {:ok, spacecraft_id} -> Enum.filter(records, &(&1.spacecraft_id == spacecraft_id))
      :error -> records
    end
  end

  defp latest_sample(%Sample{} = sample, %Sample{} = existing_sample) do
    if sample_newer?(sample, existing_sample), do: sample, else: existing_sample
  end

  defp sample_newer?(%Sample{} = sample, %Sample{} = existing_sample) do
    LatestProjectionOrder.newer?(sample, existing_sample, :sample_id)
  end

  defp opts_from_run(%Run{metadata: metadata}) when is_map(metadata) do
    []
    |> maybe_put_opt(
      :spacecraft_id,
      Map.get(metadata, "spacecraft_id", Map.get(metadata, :spacecraft_id))
    )
    |> maybe_put_opt(:realm, Map.get(metadata, "realm", Map.get(metadata, :realm)))
    |> maybe_put_opt(
      :data_source_id,
      Map.get(metadata, "data_source_id", Map.get(metadata, :data_source_id))
    )
    |> maybe_put_opt(
      :source_binding_id,
      Map.get(metadata, "source_binding_id", Map.get(metadata, :source_binding_id))
    )
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, _key, ""), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

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
        {:error, :rebuild_run_not_found}

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
