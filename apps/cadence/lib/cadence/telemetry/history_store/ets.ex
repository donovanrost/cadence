defmodule Cadence.Telemetry.HistoryStore.ETS do
  @moduledoc """
  ETS-backed telemetry history window for low-latency local runtime reads.
  """

  use GenServer

  @behaviour Cadence.Telemetry.HistoryStore

  alias Cadence.Telemetry.Sample

  @mission_scope_key "__mission__"
  @table_name :cadence_telemetry_history
  @default_max_samples_per_point :infinity

  @impl true
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    _table =
      :ets.new(@table_name, [
        :named_table,
        :public,
        :ordered_set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, @table_name}
  end

  @impl true
  def persist_samples(samples) when is_list(samples) do
    table = ensure_table!()

    samples
    |> Enum.each(fn %Sample{} = sample ->
      true = :ets.insert(table, {key(sample), sample})
    end)

    prune_points(table, samples)
    :ok
  end

  @impl true
  def sample_history(mission_id, point_id, opts) do
    table = ensure_table!()
    spacecraft_filter = Keyword.get(opts, :spacecraft_id)
    from_receipt_time = Keyword.get(opts, :from_receipt_time)
    to_receipt_time = Keyword.get(opts, :to_receipt_time)
    order = Keyword.get(opts, :order, :desc)
    limit = Keyword.get(opts, :limit, 100)

    table
    |> samples_for_point(mission_id, point_id, spacecraft_filter)
    |> filter_from_receipt_time(from_receipt_time)
    |> filter_to_receipt_time(to_receipt_time)
    |> sort_history(order)
    |> Enum.take(limit)
  end

  @impl true
  def reset do
    table = ensure_table!()
    true = :ets.delete_all_objects(table)
    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@table_name) do
      :undefined -> raise "#{inspect(__MODULE__)} is not started"
      table -> table
    end
  end

  defp samples_for_point(table, mission_id, point_id, spacecraft_filter) do
    :ets.foldl(
      fn
        {{^mission_id, stored_scope_id, ^point_id, _receipt_us, _sample_id}, %Sample{} = sample},
        acc ->
          if is_nil(spacecraft_filter) or
               stored_scope_id == spacecraft_scope_id(spacecraft_filter) do
            [sample | acc]
          else
            acc
          end

        _entry, acc ->
          acc
      end,
      [],
      table
    )
  end

  defp filter_from_receipt_time(samples, nil), do: samples

  defp filter_from_receipt_time(samples, %DateTime{} = from_receipt_time) do
    Enum.filter(samples, &(DateTime.compare(&1.receipt_time, from_receipt_time) != :lt))
  end

  defp filter_to_receipt_time(samples, nil), do: samples

  defp filter_to_receipt_time(samples, %DateTime{} = to_receipt_time) do
    Enum.filter(samples, &(DateTime.compare(&1.receipt_time, to_receipt_time) != :gt))
  end

  defp sort_history(samples, :asc), do: Enum.sort_by(samples, &sort_key/1, :asc)
  defp sort_history(samples, _order), do: Enum.sort_by(samples, &sort_key/1, :desc)

  defp prune_points(table, samples) do
    case max_samples_per_point() do
      :infinity ->
        :ok

      max_samples when is_integer(max_samples) and max_samples > 0 ->
        samples
        |> Enum.map(&point_key/1)
        |> Enum.uniq()
        |> Enum.each(&prune_point(table, &1, max_samples))
    end
  end

  defp prune_point(table, {mission_id, spacecraft_scope_id, point_id}, max_samples) do
    keys =
      :ets.foldl(
        fn
          {{^mission_id, ^spacecraft_scope_id, ^point_id, _receipt_us, _sample_id} = key,
           %Sample{}},
          acc ->
            [key | acc]

          _entry, acc ->
            acc
        end,
        [],
        table
      )
      |> Enum.sort(:desc)

    keys
    |> Enum.drop(max_samples)
    |> Enum.each(&:ets.delete(table, &1))
  end

  defp max_samples_per_point do
    Application.get_env(:cadence, :telemetry_history_store, [])
    |> Keyword.get(:max_samples_per_point, @default_max_samples_per_point)
  end

  defp key(%Sample{} = sample) do
    {mission_id, spacecraft_scope_id, point_id} = point_key(sample)
    {mission_id, spacecraft_scope_id, point_id, receipt_us(sample), sample.sample_id}
  end

  defp point_key(%Sample{} = sample) do
    {sample.mission_id, spacecraft_scope_id(sample.spacecraft_id), sample.point_id}
  end

  defp sort_key(%Sample{} = sample), do: {receipt_us(sample), sample.sample_id}

  defp receipt_us(%Sample{receipt_time: %DateTime{} = receipt_time}) do
    DateTime.to_unix(receipt_time, :microsecond)
  end

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id
end
