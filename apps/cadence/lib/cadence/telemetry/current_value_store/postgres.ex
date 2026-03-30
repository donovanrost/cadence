defmodule Cadence.Telemetry.CurrentValueStore.Postgres do
  @moduledoc """
  Postgres-backed current value table used for tests and rebuild flows.
  """

  @behaviour Cadence.Telemetry.CurrentValueStore

  import Ecto.Query

  alias Cadence.Persistence.Schemas.TelemetryLatestValueRow
  alias Cadence.Repo
  alias Cadence.Telemetry.Sample

  @mission_scope_key "__mission__"

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def hot_path_safe?, do: false

  @impl true
  def record_samples(samples) when is_list(samples) do
    case Repo.transaction(fn ->
           Enum.reduce_while(samples, :ok, fn %Sample{} = sample, :ok ->
             case persist_latest_value(sample) do
               {:ok, _row} -> {:cont, :ok}
               {:error, reason} -> Repo.rollback(reason)
             end
           end)
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def latest_value(mission_id, point_id, opts) do
    mission_id
    |> latest_value_query(point_id, opts)
    |> Repo.one()
    |> maybe_to_sample()
  end

  @impl true
  def latest_values_for_mission(mission_id, opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    query =
      TelemetryLatestValueRow
      |> where([row], row.mission_id == ^mission_id)
      |> maybe_filter_spacecraft(spacecraft_scope_id, opts)
      |> order_by([row], asc: row.point_name)

    query
    |> Repo.all()
    |> Enum.map(&TelemetryLatestValueRow.to_domain/1)
  end

  @impl true
  def reset do
    _ = Repo.delete_all(TelemetryLatestValueRow)
    :ok
  end

  @impl true
  def reset(mission_id) when is_binary(mission_id) do
    _ =
      TelemetryLatestValueRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.delete_all()

    :ok
  end

  defp persist_latest_value(%Sample{} = sample) do
    existing_row =
      Repo.get_by(TelemetryLatestValueRow,
        mission_id: sample.mission_id,
        spacecraft_scope_id: spacecraft_scope_id(sample.spacecraft_id),
        point_id: sample.point_id
      )

    cond do
      is_nil(existing_row) ->
        %TelemetryLatestValueRow{}
        |> TelemetryLatestValueRow.changeset(sample)
        |> Repo.insert()

      sample_newer?(sample, existing_row) ->
        existing_row
        |> TelemetryLatestValueRow.changeset(sample)
        |> Repo.update()

      true ->
        {:ok, existing_row}
    end
  end

  defp latest_value_query(mission_id, point_id, opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    TelemetryLatestValueRow
    |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
    |> maybe_filter_spacecraft(spacecraft_scope_id, opts)
    |> order_by([row], desc: row.receipt_time, desc: row.generation_time, desc: row.sample_id)
    |> limit(1)
  end

  defp maybe_filter_spacecraft(query, spacecraft_scope_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      where(query, [row], row.spacecraft_scope_id == ^spacecraft_scope_id)
    else
      query
    end
  end

  defp maybe_to_sample(nil), do: nil
  defp maybe_to_sample(row), do: TelemetryLatestValueRow.to_domain(row)

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id

  defp sample_newer?(%Sample{} = sample, %TelemetryLatestValueRow{} = latest_value_row) do
    compare_sort_keys(sample_sort_key(sample), row_sort_key(latest_value_row)) == :gt
  end

  defp sample_sort_key(%Sample{} = sample) do
    {sample.generation_time || sample.receipt_time, sample.receipt_time, sample.sample_id}
  end

  defp row_sort_key(%TelemetryLatestValueRow{} = row) do
    {row.generation_time || row.receipt_time, row.receipt_time, row.sample_id}
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

  defp compare_ids(id_a, id_b) when is_binary(id_a) and is_binary(id_b) do
    cond do
      id_a > id_b -> :gt
      id_a < id_b -> :lt
      true -> :eq
    end
  end
end
