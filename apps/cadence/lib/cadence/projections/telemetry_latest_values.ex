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
    TelemetryObservationIdentityStateRow,
    TelemetrySampleRow
  }

  alias Cadence.Projections.TelemetryLatestValues.Run
  alias Cadence.Repo
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.EffectiveSelection
  alias Cadence.Telemetry.LatestProjectionOrder
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.SourceFilters

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

    sample_rows =
      TelemetrySampleRow
      |> where([sample_row], sample_row.mission_id == ^mission_id)
      |> maybe_filter_spacecraft(spacecraft_id)
      |> Repo.all()

    latest_samples =
      sample_rows
      |> latest_samples_for_rows(identity_rows_for_mission(mission_id, opts), opts)

    Repo.transaction(fn ->
      TelemetryLatestValueRow
      |> where([latest_value_row], latest_value_row.mission_id == ^mission_id)
      |> maybe_filter_latest_spacecraft(spacecraft_id)
      |> maybe_filter_latest_source(opts)
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

  defp maybe_filter_exact_spacecraft(query, opts) do
    case Keyword.fetch(opts, :spacecraft_id) do
      {:ok, nil} -> where(query, [row], is_nil(row.spacecraft_id))
      {:ok, spacecraft_id} -> where(query, [row], row.spacecraft_id == ^spacecraft_id)
      :error -> query
    end
  end

  defp maybe_filter_latest_spacecraft(query, nil), do: query

  defp maybe_filter_latest_spacecraft(query, spacecraft_id) do
    where(query, [latest_value_row], latest_value_row.spacecraft_scope_id == ^spacecraft_id)
  end

  defp maybe_filter_latest_source(query, opts) do
    opts
    |> SourceFilters.normalize()
    |> Enum.reduce(query, fn
      {:realm, realm}, query ->
        where(query, [latest_value_row], latest_value_row.realm == ^realm)

      {:data_source_id, data_source_id}, query ->
        where(query, [latest_value_row], latest_value_row.data_source_id == ^data_source_id)

      {:binding_id, binding_id}, query ->
        where(query, [latest_value_row], latest_value_row.binding_id == ^binding_id)

      {:source_endpoint_ids, source_endpoint_ids}, query ->
        where(
          query,
          [latest_value_row],
          fragment("?->'storage'->>'source_endpoint_id'", latest_value_row.provenance) in ^source_endpoint_ids
        )
    end)
  end

  defp sample_rows_for_point(mission_id, point_id, opts) do
    TelemetrySampleRow
    |> where(
      [sample_row],
      sample_row.mission_id == ^mission_id and sample_row.point_id == ^point_id
    )
    |> maybe_filter_exact_spacecraft(opts)
    |> Repo.all()
  end

  defp identity_rows_for_point(mission_id, point_id, opts) do
    TelemetryObservationIdentityStateRow
    |> where([identity_state], identity_state.mission_id == ^mission_id)
    |> where([identity_state], identity_state.point_id == ^point_id)
    |> maybe_filter_exact_spacecraft(opts)
    |> maybe_filter_identity_source(opts)
    |> Repo.all()
  end

  defp identity_rows_for_mission(mission_id, opts) do
    TelemetryObservationIdentityStateRow
    |> where([identity_state], identity_state.mission_id == ^mission_id)
    |> maybe_filter_spacecraft(Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_identity_source(opts)
    |> Repo.all()
  end

  defp maybe_filter_identity_source(query, opts) do
    opts
    |> SourceFilters.normalize()
    |> Enum.reduce(query, fn
      {:realm, realm}, query ->
        where(query, [identity_state], identity_state.realm == ^realm)

      {:data_source_id, data_source_id}, query ->
        where(query, [identity_state], identity_state.data_source_id == ^data_source_id)

      {:binding_id, binding_id}, query ->
        where(query, [identity_state], identity_state.binding_id == ^binding_id)

      {:source_endpoint_ids, _source_endpoint_ids}, query ->
        query
    end)
  end

  defp latest_sample_for_rows(sample_rows, identity_rows, opts) do
    sample_rows
    |> effective_selected_samples(identity_rows, opts)
    |> Enum.reduce(nil, fn
      %Sample{} = sample, nil -> sample
      %Sample{} = sample, %Sample{} = latest -> latest_sample(sample, latest)
    end)
  end

  defp latest_samples_for_rows(sample_rows, identity_rows, opts) do
    sample_rows
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

  defp effective_selected_samples(sample_rows, identity_rows, opts) do
    sample_rows
    |> Enum.map(&TelemetrySampleRow.to_domain/1)
    |> SourceFilters.filter_samples(opts)
    |> EffectiveSelection.selected_samples(identity_rows, opts)
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
