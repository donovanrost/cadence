defmodule Cadence.Telemetry.HistoryStore.ETS do
  @moduledoc """
  ETS-backed telemetry history window for low-latency local runtime reads.
  """

  use GenServer

  @behaviour Cadence.Telemetry.HistoryStore

  alias Cadence.Telemetry.{Sample, SelectionPolicy, SourceFilters}

  @mission_scope_key "__mission__"
  @table_name :cadence_telemetry_history
  @config_table_name :cadence_telemetry_history_config
  @default_max_samples_per_point :infinity

  @impl true
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :child_id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, @table_name)
    config_table_name = Keyword.get(opts, :config_table_name, @config_table_name)

    _table =
      :ets.new(table_name, [
        :named_table,
        :public,
        :ordered_set,
        read_concurrency: true,
        write_concurrency: true
      ])

    _config_table =
      :ets.new(config_table_name, [
        :named_table,
        :protected,
        :set,
        read_concurrency: true
      ])

    true =
      :ets.insert(
        config_table_name,
        {:max_samples_per_point,
         Keyword.get(opts, :max_samples_per_point, @default_max_samples_per_point)}
      )

    {:ok, %{config_table_name: config_table_name, table_name: table_name}}
  end

  @impl true
  def persist_samples(samples) when is_list(samples), do: persist_samples(samples, [])

  @impl true
  def persist_samples(samples, backend_opts) when is_list(samples) and is_list(backend_opts) do
    table = ensure_table!(backend_opts, :table_name, @table_name)
    config_table = ensure_table!(backend_opts, :config_table_name, @config_table_name)

    samples
    |> Enum.each(fn %Sample{} = sample ->
      true = :ets.insert(table, {key(sample), sample})
    end)

    prune_points(table, config_table, samples)
    :ok
  end

  @impl true
  def sample_history(mission_id, point_id, opts),
    do: sample_history(mission_id, point_id, opts, [])

  @impl true
  def sample_history(mission_id, point_id, opts, backend_opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) and
             is_list(backend_opts) do
    table = ensure_table!(backend_opts, :table_name, @table_name)
    spacecraft_filter = Keyword.get(opts, :spacecraft_id)
    from_receipt_time = Keyword.get(opts, :from_receipt_time)
    to_receipt_time = Keyword.get(opts, :to_receipt_time)
    from_observed_at = Keyword.get(opts, :from_observed_at)
    to_observed_at = Keyword.get(opts, :to_observed_at)
    order = Keyword.get(opts, :order, :desc)
    time_axis = Keyword.get(opts, :time_axis)
    limit = Keyword.get(opts, :limit, 100)

    table
    |> samples_for_point(mission_id, point_id, spacecraft_filter)
    |> filter_from_receipt_time(from_receipt_time)
    |> filter_to_receipt_time(to_receipt_time)
    |> filter_from_observed_at(from_observed_at)
    |> filter_to_observed_at(to_observed_at)
    |> SourceFilters.filter_samples(opts)
    |> SelectionPolicy.selected_samples(opts)
    |> sort_history(order, time_axis)
    |> Enum.take(limit)
  end

  @impl true
  def reset, do: reset([])

  @impl true
  def reset(backend_opts) when is_list(backend_opts) do
    table = ensure_table!(backend_opts, :table_name, @table_name)
    true = :ets.delete_all_objects(table)
    :ok
  end

  defp ensure_table!(backend_opts, option, default) do
    table_name = Keyword.get(backend_opts, option, default)

    case :ets.whereis(table_name) do
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

  defp filter_from_observed_at(samples, nil), do: samples

  defp filter_from_observed_at(samples, %DateTime{} = from_observed_at) do
    Enum.filter(samples, fn %Sample{} = sample ->
      case observed_at(sample) do
        %DateTime{} = datetime -> DateTime.compare(datetime, from_observed_at) != :lt
        nil -> false
      end
    end)
  end

  defp filter_to_observed_at(samples, nil), do: samples

  defp filter_to_observed_at(samples, %DateTime{} = to_observed_at) do
    Enum.filter(samples, fn %Sample{} = sample ->
      case observed_at(sample) do
        %DateTime{} = datetime -> DateTime.compare(datetime, to_observed_at) != :gt
        nil -> false
      end
    end)
  end

  defp sort_history(samples, :asc, axis) when axis in [:generation_time, "generation_time"],
    do: Enum.sort_by(samples, &observed_sort_key/1, :asc)

  defp sort_history(samples, _order, axis) when axis in [:generation_time, "generation_time"],
    do: Enum.sort_by(samples, &observed_sort_key/1, :desc)

  defp sort_history(samples, :asc, _axis), do: Enum.sort_by(samples, &sort_key/1, :asc)
  defp sort_history(samples, _order, _axis), do: Enum.sort_by(samples, &sort_key/1, :desc)

  defp prune_points(table, config_table, samples) do
    case max_samples_per_point(config_table) do
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

  defp max_samples_per_point(config_table) do
    case :ets.lookup(config_table, :max_samples_per_point) do
      [{:max_samples_per_point, value}] -> value
      [] -> @default_max_samples_per_point
    end
  end

  defp key(%Sample{} = sample) do
    {mission_id, spacecraft_scope_id, point_id} = point_key(sample)
    {mission_id, spacecraft_scope_id, point_id, receipt_us(sample), sample.sample_id}
  end

  defp point_key(%Sample{} = sample) do
    {sample.mission_id, spacecraft_scope_id(sample.spacecraft_id), sample.point_id}
  end

  defp sort_key(%Sample{} = sample), do: {receipt_us(sample), sample.sample_id}

  defp observed_sort_key(%Sample{} = sample) do
    observed_time =
      case observed_at(sample) do
        %DateTime{} = datetime -> DateTime.to_unix(datetime, :microsecond)
        nil -> receipt_us(sample)
      end

    {observed_time, receipt_us(sample), sample.sample_id}
  end

  defp observed_at(%Sample{generation_time: %DateTime{} = generation_time}), do: generation_time
  defp observed_at(%Sample{receipt_time: %DateTime{} = receipt_time}), do: receipt_time
  defp observed_at(%Sample{}), do: nil

  defp receipt_us(%Sample{receipt_time: %DateTime{} = receipt_time}) do
    DateTime.to_unix(receipt_time, :microsecond)
  end

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id
end
