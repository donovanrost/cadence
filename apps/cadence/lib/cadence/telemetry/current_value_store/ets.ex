defmodule Cadence.Telemetry.CurrentValueStore.ETS do
  @moduledoc """
  ETS-backed current value table for low-latency mission reads.
  """

  use GenServer

  @behaviour Cadence.Telemetry.CurrentValueStore

  alias Cadence.Telemetry.{LatestProjectionOrder, SelectionPolicy, SourceFilters}
  alias Cadence.Telemetry.Sample

  @mission_scope_key "__mission__"
  @table_name :cadence_telemetry_current_values

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
  def hot_path_safe?, do: true

  @impl true
  def hot_path_safe?(_backend_opts), do: true

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, @table_name)

    _table =
      :ets.new(table_name, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    # The newest receipt time per (mission, spacecraft), kept as values are recorded, so the fleet
    # read asks for it instead of reading every value (#798).
    _receipts =
      :ets.new(receipts_table_name(table_name), [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    # The keys of each spacecraft's values, added when a key first appears (a new point, not each
    # sample), so one spacecraft's values are a lookup of its keys instead of a pass over every
    # value on the node (#143). A key deleted since stays listed; a read skips it.
    _index =
      :ets.new(index_table_name(table_name), [
        :named_table,
        :public,
        :ordered_set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, table_name}
  end

  defp receipts_table_name(table_name), do: :"#{table_name}_receipts"
  defp index_table_name(table_name), do: :"#{table_name}_by_spacecraft"

  defp index_table(backend_opts) do
    backend_opts |> Keyword.get(:table_name, @table_name) |> index_table_name()
  end

  # An object is the 1-tuple of its key, `{{mission, scope}, key}`, so that the spacecraft's keys
  # are a prefix range of the ordered set.
  defp index_entry({mission_id, scope_id, _point, _realm, _source, _binding} = key),
    do: {{{mission_id, scope_id}, key}}

  @impl true
  def record_samples(samples) when is_list(samples), do: record_samples(samples, [])

  @impl true
  def record_samples(samples, backend_opts) when is_list(samples) and is_list(backend_opts) do
    table = ensure_table!(backend_opts)

    samples
    |> SelectionPolicy.selected_samples([])
    |> latest_per_key()
    |> Enum.each(fn {key, sample} ->
      maybe_store_sample(table, index_table(backend_opts), key, sample)
      note_receipt(backend_opts, sample)
    end)

    :ok
  end

  # An atomic max: replace the stored time only when the new one is later, else insert if absent.
  defp note_receipt(backend_opts, %Sample{receipt_time: %DateTime{} = at} = sample) do
    table = receipts_table(backend_opts)
    key = {sample.mission_id, spacecraft_scope_id(sample.spacecraft_id)}
    micros = DateTime.to_unix(at, :microsecond)

    replaced =
      :ets.select_replace(table, [
        {{key, :"$1"}, [{:<, :"$1", micros}], [{{{:const, key}, micros}}]}
      ])

    if replaced == 0, do: :ets.insert_new(table, {key, micros})
    :ok
  end

  defp note_receipt(_backend_opts, _sample), do: :ok

  defp receipts_table(backend_opts) do
    backend_opts |> Keyword.get(:table_name, @table_name) |> receipts_table_name()
  end

  @impl true
  def last_receipts(mission_id, backend_opts) when is_binary(mission_id) do
    _ = ensure_table!(backend_opts)

    backend_opts
    |> receipts_table()
    |> :ets.select([
      {{{mission_id, :"$1"}, :"$2"}, [{:"=/=", :"$1", @mission_scope_key}], [{{:"$1", :"$2"}}]}
    ])
    |> Map.new(fn {scope_id, micros} -> {scope_id, DateTime.from_unix!(micros, :microsecond)} end)
  end

  @impl true
  def replace_value(mission_id, point_id, sample_or_nil, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    replace_value(mission_id, point_id, sample_or_nil, opts, [])
  end

  @impl true
  def replace_value(mission_id, point_id, nil, opts, backend_opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) and
             is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    table
    |> keys_for_point(mission_id, spacecraft_scope_id, point_id, opts)
    |> Enum.each(&:ets.delete(table, &1))

    :ok
  end

  def replace_value(mission_id, point_id, %Sample{} = sample, opts, backend_opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) and
             is_list(backend_opts) do
    with :ok <- validate_replacement_scope(mission_id, point_id, sample) do
      table = ensure_table!(backend_opts)
      true = :ets.insert(table, {key(sample), sample})
      true = :ets.insert(index_table(backend_opts), index_entry(key(sample)))
      note_receipt(backend_opts, sample)
      :ok
    end
  end

  @impl true
  def replace_values_for_scope(mission_id, samples, opts),
    do: replace_values_for_scope(mission_id, samples, opts, [])

  @impl true
  def replace_values_for_scope(mission_id, samples, opts, backend_opts)
      when is_binary(mission_id) and is_list(samples) and is_list(opts) and
             is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    spacecraft_filter = Keyword.get(opts, :spacecraft_id)

    :ets.foldl(
      fn
        {{^mission_id, stored_scope_id, _point_id, _realm, _data_source_id, _binding_id} = key,
         %Sample{} = sample},
        :ok ->
          if (is_nil(spacecraft_filter) or
                stored_scope_id == spacecraft_scope_id(spacecraft_filter)) and
               SourceFilters.sample_matches?(sample, opts) do
            true = :ets.delete(table, key)
          end

          :ok

        _entry, :ok ->
          :ok
      end,
      :ok,
      table
    )

    Enum.each(samples, fn %Sample{} = sample ->
      true = :ets.insert(table, {key(sample), sample})
      true = :ets.insert(index_table(backend_opts), index_entry(key(sample)))
      note_receipt(backend_opts, sample)
    end)

    :ok
  end

  @impl true
  def latest_value(mission_id, point_id, opts), do: latest_value(mission_id, point_id, opts, [])

  @impl true
  def latest_value(mission_id, point_id, opts, backend_opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) and
             is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    table
    |> samples_for_point(mission_id, spacecraft_scope_id, point_id, opts)
    |> Enum.reduce(nil, fn
      %Sample{} = sample, nil -> sample
      %Sample{} = sample, %Sample{} = latest_sample -> latest_sample(sample, latest_sample)
    end)
  end

  @impl true
  def latest_values_for_mission(mission_id, opts),
    do: latest_values_for_mission(mission_id, opts, [])

  @impl true
  def latest_values_for_mission(mission_id, opts, backend_opts)
      when is_binary(mission_id) and is_list(opts) and is_list(backend_opts) do
    spacecraft_filter = Keyword.get(opts, :spacecraft_id)
    spacecraft_ids = id_set(Keyword.get(opts, :spacecraft_ids))
    table = ensure_table!(backend_opts)

    table
    |> entries(mission_id, spacecraft_filter, opts, backend_opts)
    |> Enum.flat_map(fn {stored_scope_id, %Sample{} = sample} ->
      if (is_nil(spacecraft_filter) or
            stored_scope_id == spacecraft_scope_id(spacecraft_filter)) and
           member?(spacecraft_ids, stored_scope_id) and
           SourceFilters.sample_matches?(sample, opts) and
           SelectionPolicy.selected_sample?(sample, opts),
         do: [sample],
         else: []
    end)
    |> Enum.sort_by(& &1.point_name)
  end

  # All of a mission's values: the match spec compares the KEY inside the table (mission, and the
  # asked points) and copies out only the entries that pass: a fleet's thousands of other points
  # are never copied. One spacecraft's: a lookup of its keys, not a pass over the node's values.
  defp entries(table, mission_id, nil, opts, _backend_opts) do
    :ets.select(table, [
      {{{mission_id, :"$1", :"$2", :_, :_, :_}, :"$3"}, point_guards(opts), [{{:"$1", :"$3"}}]}
    ])
  end

  defp entries(table, mission_id, spacecraft_id, opts, backend_opts) do
    scope_id = spacecraft_scope_id(spacecraft_id)
    points = opts |> Keyword.get(:point_ids) |> id_set()

    backend_opts
    |> index_table()
    |> :ets.select([{{{{mission_id, scope_id}, :"$1"}}, [], [:"$1"]}])
    |> Enum.flat_map(fn {_m, _s, point_id, _r, _d, _b} = key ->
      with true <- member?(points, point_id),
           [{^key, sample}] <- :ets.lookup(table, key) do
        [{scope_id, sample}]
      else
        _skip -> []
      end
    end)
  end

  # `:point_ids` restricts the read to those points (a guard on the key's point), `:spacecraft_ids`
  # to those spacecraft (checked on what the guard let through: the spacecraft list can be long).
  defp point_guards(opts) do
    case Keyword.get(opts, :point_ids) do
      nil -> []
      [] -> [{:"=:=", 1, 0}]
      ids -> [List.to_tuple([:orelse | Enum.map(ids, &{:"=:=", :"$2", &1})])]
    end
  end

  defp id_set(nil), do: nil
  defp id_set(ids) when is_list(ids), do: MapSet.new(ids)

  defp member?(nil, _id), do: true
  defp member?(set, id), do: MapSet.member?(set, id)

  @impl true
  def reset, do: reset(:all, [])

  @impl true
  def reset(mission_id) when is_binary(mission_id), do: reset(mission_id, [])

  @impl true
  def reset(:all, backend_opts) when is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    true = :ets.delete_all_objects(table)
    true = :ets.delete_all_objects(receipts_table(backend_opts))
    true = :ets.delete_all_objects(index_table(backend_opts))
    :ok
  end

  def reset(mission_id, backend_opts) when is_binary(mission_id) and is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    true = :ets.match_delete(table, {{mission_id, :_, :_, :_, :_, :_}, :_})
    true = :ets.match_delete(receipts_table(backend_opts), {{mission_id, :_}, :_})
    true = :ets.match_delete(index_table(backend_opts), {{{mission_id, :_}, :_}})
    :ok
  end

  defp ensure_table!(backend_opts) do
    table_name = Keyword.get(backend_opts, :table_name, @table_name)

    case :ets.whereis(table_name) do
      :undefined -> raise "#{inspect(__MODULE__)} is not started"
      table -> table
    end
  end

  defp latest_per_key(samples) do
    Enum.reduce(samples, %{}, fn %Sample{} = sample, acc ->
      key = key(sample)

      Map.update(acc, key, sample, &latest_sample(sample, &1))
    end)
  end

  defp maybe_store_sample(table, index, key, %Sample{} = sample) do
    case :ets.lookup(table, key) do
      [{^key, existing_sample}] ->
        maybe_insert_newer_sample(table, key, sample, existing_sample)

      [] ->
        true = :ets.insert(table, {key, sample})
        true = :ets.insert(index, index_entry(key))
    end
  end

  defp maybe_insert_newer_sample(table, key, %Sample{} = sample, %Sample{} = existing_sample) do
    if sample_newer?(sample, existing_sample) do
      true = :ets.insert(table, {key, sample})
    end
  end

  defp latest_sample(%Sample{} = sample, %Sample{} = existing_sample) do
    if sample_newer?(sample, existing_sample), do: sample, else: existing_sample
  end

  defp key(%Sample{} = sample) do
    {realm, data_source_id, binding_id} = SourceFilters.sample_key(sample)

    {
      sample.mission_id,
      spacecraft_scope_id(sample.spacecraft_id),
      sample.point_id,
      realm,
      data_source_id,
      binding_id
    }
  end

  defp keys_for_point(table, mission_id, spacecraft_scope_id, point_id, opts) do
    table
    |> samples_for_point(mission_id, spacecraft_scope_id, point_id, opts)
    |> Enum.map(&key/1)
  end

  defp samples_for_point(table, mission_id, spacecraft_scope_id, point_id, opts) do
    :ets.foldl(
      fn
        {{^mission_id, ^spacecraft_scope_id, ^point_id, _realm, _data_source_id, _binding_id},
         %Sample{} = sample},
        acc ->
          if SourceFilters.sample_matches?(sample, opts) and
               SelectionPolicy.selected_sample?(sample, opts) do
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

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id

  defp validate_replacement_scope(mission_id, point_id, %Sample{} = sample) do
    cond do
      sample.mission_id != mission_id ->
        {:error, {:mission_mismatch, mission_id, sample.mission_id}}

      sample.point_id != point_id ->
        {:error, {:point_mismatch, point_id, sample.point_id}}

      true ->
        :ok
    end
  end

  defp sample_newer?(%Sample{} = sample, %Sample{} = existing_sample) do
    LatestProjectionOrder.newer?(sample, existing_sample, :sample_id)
  end
end
