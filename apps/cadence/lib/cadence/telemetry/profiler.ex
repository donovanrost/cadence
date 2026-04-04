defmodule Cadence.Telemetry.Profiler do
  @moduledoc """
  Lightweight downlink-ingress profiler for the current Cadence runtime.

  The profiler is intentionally hot-path friendly:

  - ingress work is tagged with mission/stage context in the process dictionary
  - `Repo` query telemetry updates mission-scoped counters directly
  - snapshots are aggregated on read from mission-scoped counter references

  This lets `mix cadence.profile` observe actual downlink behavior while the
  simulator is exercising the runtime.
  """

  use GenServer

  alias Cadence.ApplicationDispatch.DispatchDecision
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.Protocol.RecordArchive

  @table_name :cadence_telemetry_profiler
  @repo_query_event [:cadence, :repo, :query]
  @repo_handler_id "#{__MODULE__}.repo-query"
  @context_key {__MODULE__, :context}
  @stage_key {__MODULE__, :stage}
  @stages [:resolve, :runtime, :persistence]
  @runtime_components [
    :runtime_boundary,
    :telemetry_sample_extraction,
    :current_value_record,
    :partition_prepare,
    :partition_decode,
    :partition_dispatch,
    :runtime_record_persistence
  ]
  @runtime_component_slot_pairs %{
    runtime_boundary: {:runtime_boundary_count, :runtime_boundary_total_us},
    telemetry_sample_extraction:
      {:telemetry_sample_extraction_count, :telemetry_sample_extraction_total_us},
    current_value_record: {:current_value_record_count, :current_value_record_total_us},
    partition_prepare: {:partition_prepare_count, :partition_prepare_total_us},
    partition_decode: {:partition_decode_count, :partition_decode_total_us},
    partition_dispatch: {:partition_dispatch_count, :partition_dispatch_total_us},
    runtime_record_persistence:
      {:runtime_record_persistence_count, :runtime_record_persistence_total_us}
  }

  @slots %{
    ingress_count: 1,
    ingress_error_count: 2,
    resolve_count: 3,
    resolve_total_us: 4,
    runtime_count: 5,
    runtime_total_us: 6,
    persistence_count: 7,
    persistence_total_us: 8,
    end_to_end_total_us: 9,
    raw_bytes_total: 10,
    packet_count: 11,
    transfer_frame_count: 12,
    anomaly_count: 13,
    dispatch_count: 14,
    work_item_count: 15,
    sample_count: 16,
    db_query_count: 17,
    db_query_total_us: 18,
    db_queue_total_us: 19,
    db_decode_total_us: 20,
    db_idle_total_us: 21,
    db_select_count: 22,
    db_insert_count: 23,
    db_update_count: 24,
    db_delete_count: 25,
    db_other_count: 26,
    db_resolve_query_count: 27,
    db_resolve_query_total_us: 28,
    db_runtime_query_count: 29,
    db_runtime_query_total_us: 30,
    db_persistence_query_count: 31,
    db_persistence_query_total_us: 32,
    runtime_boundary_count: 33,
    runtime_boundary_total_us: 34,
    telemetry_sample_extraction_count: 35,
    telemetry_sample_extraction_total_us: 36,
    current_value_record_count: 37,
    current_value_record_total_us: 38,
    partition_prepare_count: 39,
    partition_prepare_total_us: 40,
    partition_decode_count: 41,
    partition_decode_total_us: 42,
    partition_dispatch_count: 43,
    partition_dispatch_total_us: 44,
    runtime_record_persistence_count: 45,
    runtime_record_persistence_total_us: 46
  }

  @slot_count map_size(@slots)

  @type snapshot :: %{
          mission_id: binary(),
          duration_sec: float(),
          ingress_count: non_neg_integer(),
          ingress_error_count: non_neg_integer(),
          raw_bytes_total: non_neg_integer(),
          packets: %{
            packet_count: non_neg_integer(),
            transfer_frame_count: non_neg_integer(),
            anomaly_count: non_neg_integer()
          },
          dispatch: %{
            dispatch_count: non_neg_integer(),
            work_item_count: non_neg_integer(),
            sample_count: non_neg_integer()
          },
          stages: %{
            resolve: %{count: non_neg_integer(), total_us: non_neg_integer(), avg_us: float()},
            runtime: %{count: non_neg_integer(), total_us: non_neg_integer(), avg_us: float()},
            persistence: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            },
            end_to_end: %{count: non_neg_integer(), total_us: non_neg_integer(), avg_us: float()}
          },
          runtime_components: %{
            runtime_boundary: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            },
            telemetry_sample_extraction: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            },
            current_value_record: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            },
            partition_prepare: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            },
            partition_decode: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            },
            partition_dispatch: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            },
            runtime_record_persistence: %{
              count: non_neg_integer(),
              total_us: non_neg_integer(),
              avg_us: float()
            }
          },
          db: %{
            query_count: non_neg_integer(),
            query_total_us: non_neg_integer(),
            query_avg_us: float(),
            queries_per_ingress: float(),
            query_time_per_ingress_us: float(),
            queue_total_us: non_neg_integer(),
            decode_total_us: non_neg_integer(),
            idle_total_us: non_neg_integer(),
            operations: %{
              select_count: non_neg_integer(),
              insert_count: non_neg_integer(),
              update_count: non_neg_integer(),
              delete_count: non_neg_integer(),
              other_count: non_neg_integer()
            },
            by_stage: %{
              resolve: %{
                query_count: non_neg_integer(),
                total_us: non_neg_integer(),
                avg_us: float()
              },
              runtime: %{
                query_count: non_neg_integer(),
                total_us: non_neg_integer(),
                avg_us: float()
              },
              persistence: %{
                query_count: non_neg_integer(),
                total_us: non_neg_integer(),
                avg_us: float()
              }
            }
          },
          archive: %{
            combined: map(),
            ingress: map(),
            protocol: map()
          }
        }

  def start_link(opts \\ []) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec with_ingress_context(RawEvidence.t(), (-> result)) :: result when result: var
  def with_ingress_context(%RawEvidence{} = raw_evidence, fun) when is_function(fun, 0) do
    previous_context = Process.get(@context_key)

    Process.put(@context_key, %{
      mission_id: raw_evidence.mission_id,
      protocol_family: raw_evidence.protocol_family,
      source_endpoint_ref: raw_evidence.source_endpoint_ref
    })

    try do
      fun.()
    after
      restore_process_key(@context_key, previous_context)
    end
  end

  @spec with_stage(:resolve | :runtime | :persistence, (-> result)) :: result when result: var
  def with_stage(stage, fun) when stage in @stages and is_function(fun, 0) do
    previous_stage = Process.get(@stage_key)
    Process.put(@stage_key, stage)

    try do
      fun.()
    after
      restore_process_key(@stage_key, previous_stage)
    end
  end

  @spec record_ingress_result(RawEvidence.t(), keyword()) :: :ok
  def record_ingress_result(%RawEvidence{} = raw_evidence, opts \\ []) when is_list(opts) do
    ref = ensure_counter(raw_evidence.mission_id)

    add(ref, :ingress_count, 1)
    add(ref, :raw_bytes_total, byte_size(raw_evidence.raw || <<>>))

    if Keyword.get(opts, :error?, false) do
      add(ref, :ingress_error_count, 1)
    end

    record_stage_timing(ref, :resolve, Keyword.get(opts, :resolve_us))
    record_stage_timing(ref, :runtime, Keyword.get(opts, :runtime_us))
    record_stage_timing(ref, :persistence, Keyword.get(opts, :persistence_us))
    add_optional(ref, :end_to_end_total_us, Keyword.get(opts, :end_to_end_us))

    case Keyword.get(opts, :processing_result) do
      %{} = processing_result ->
        add(ref, :packet_count, length(Map.get(processing_result, :packet_records, [])))

        add(
          ref,
          :transfer_frame_count,
          length(Map.get(processing_result, :transfer_frame_records, []))
        )

        add(ref, :anomaly_count, length(Map.get(processing_result, :protocol_anomalies, [])))

        dispatch_decisions = Map.get(processing_result, :dispatch_decisions, [])

        add(ref, :dispatch_count, length(dispatch_decisions))

        add(
          ref,
          :work_item_count,
          Enum.reduce(dispatch_decisions, 0, fn
            %DispatchDecision{work_items: work_items}, acc when is_list(work_items) ->
              acc + length(work_items)

            _dispatch_decision, acc ->
              acc
          end)
        )

        add(
          ref,
          :sample_count,
          Enum.count(Map.get(processing_result, :outputs, []), &telemetry_sample?/1)
        )

      _other ->
        :ok
    end

    :ok
  end

  @spec record_projected_persistence(binary(), non_neg_integer(), non_neg_integer()) :: :ok
  def record_projected_persistence(mission_id, persisted_count, total_us)
      when is_binary(mission_id) and is_integer(persisted_count) and persisted_count >= 0 and
             is_integer(total_us) and total_us >= 0 do
    ref = ensure_counter(mission_id)

    add(ref, :persistence_count, persisted_count)
    add(ref, :persistence_total_us, total_us)

    :ok
  end

  @spec with_runtime_component(binary(), atom(), (-> result)) :: result when result: var
  def with_runtime_component(mission_id, component, fun)
      when is_binary(mission_id) and component in @runtime_components and is_function(fun, 0) do
    started_at = System.monotonic_time()

    try do
      fun.()
    after
      record_runtime_component(mission_id, component, elapsed_since_us(started_at))
    end
  end

  @spec snapshot(binary()) :: snapshot()
  def snapshot(mission_id) when is_binary(mission_id) do
    ensure_table()

    case :ets.lookup(@table_name, mission_id) do
      [{^mission_id, ref, started_at_ms}] ->
        build_snapshot(mission_id, ref, started_at_ms)

      [] ->
        empty_snapshot(mission_id)
    end
  end

  @spec reset(binary()) :: :ok
  def reset(mission_id) when is_binary(mission_id) do
    ensure_table()
    _ = :ets.delete(@table_name, mission_id)
    :ok = IngressArchive.reset_stats(mission_id)
    :ok = RecordArchive.reset_stats(mission_id)
    :ok
  end

  @spec list_missions() :: [binary()]
  def list_missions do
    ensure_table()

    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {mission_id, _ref, _started_at_ms} -> mission_id end)
    |> Enum.sort()
  end

  @impl true
  def init(_opts) do
    ensure_table()
    attach_repo_query_handler()
    {:ok, %{}}
  end

  def handle_event(_event_name, measurements, metadata, _config) do
    case Process.get(@context_key) do
      %{mission_id: mission_id} when is_binary(mission_id) ->
        ref = ensure_counter(mission_id)
        query_total_us = native_to_us(Map.get(measurements, :total_time))

        add(ref, :db_query_count, 1)
        add(ref, :db_query_total_us, query_total_us)
        add_optional(ref, :db_queue_total_us, native_to_us(Map.get(measurements, :queue_time)))
        add_optional(ref, :db_decode_total_us, native_to_us(Map.get(measurements, :decode_time)))
        add_optional(ref, :db_idle_total_us, native_to_us(Map.get(measurements, :idle_time)))

        record_operation(ref, classify_operation(metadata))
        record_stage_query(ref, Process.get(@stage_key), query_total_us)

        :ok

      _other ->
        :ok
    end
  end

  defp attach_repo_query_handler do
    case :telemetry.attach(@repo_handler_id, @repo_query_event, &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp ensure_table do
    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _info ->
        @table_name
    end
  end

  defp ensure_counter(mission_id) when is_binary(mission_id) do
    ensure_table()

    case :ets.lookup(@table_name, mission_id) do
      [{^mission_id, ref, _started_at_ms}] ->
        ref

      [] ->
        ref = :counters.new(@slot_count, [])
        started_at_ms = System.monotonic_time(:millisecond)
        _ = :ets.insert_new(@table_name, {mission_id, ref, started_at_ms})

        case :ets.lookup(@table_name, mission_id) do
          [{^mission_id, resolved_ref, _started_at_ms}] -> resolved_ref
          [] -> ref
        end
    end
  end

  defp build_snapshot(mission_id, ref, started_at_ms) do
    ingress_count = slot_value(ref, :ingress_count)
    resolve_count = slot_value(ref, :resolve_count)
    runtime_count = slot_value(ref, :runtime_count)
    persistence_count = slot_value(ref, :persistence_count)
    db_query_count = slot_value(ref, :db_query_count)

    now_ms = System.monotonic_time(:millisecond)
    duration_sec = max(now_ms - started_at_ms, 0) / 1000.0

    %{
      mission_id: mission_id,
      duration_sec: duration_sec,
      ingress_count: ingress_count,
      ingress_error_count: slot_value(ref, :ingress_error_count),
      raw_bytes_total: slot_value(ref, :raw_bytes_total),
      packets: %{
        packet_count: slot_value(ref, :packet_count),
        transfer_frame_count: slot_value(ref, :transfer_frame_count),
        anomaly_count: slot_value(ref, :anomaly_count)
      },
      dispatch: %{
        dispatch_count: slot_value(ref, :dispatch_count),
        work_item_count: slot_value(ref, :work_item_count),
        sample_count: slot_value(ref, :sample_count)
      },
      stages: %{
        resolve: stage_snapshot(ref, :resolve, resolve_count),
        runtime: stage_snapshot(ref, :runtime, runtime_count),
        persistence: stage_snapshot(ref, :persistence, persistence_count),
        end_to_end: %{
          count: ingress_count,
          total_us: slot_value(ref, :end_to_end_total_us),
          avg_us: average(slot_value(ref, :end_to_end_total_us), ingress_count)
        }
      },
      runtime_components: runtime_component_snapshot(ref),
      db: %{
        query_count: db_query_count,
        query_total_us: slot_value(ref, :db_query_total_us),
        query_avg_us: average(slot_value(ref, :db_query_total_us), db_query_count),
        queries_per_ingress: average(db_query_count, ingress_count),
        query_time_per_ingress_us: average(slot_value(ref, :db_query_total_us), ingress_count),
        queue_total_us: slot_value(ref, :db_queue_total_us),
        decode_total_us: slot_value(ref, :db_decode_total_us),
        idle_total_us: slot_value(ref, :db_idle_total_us),
        operations: %{
          select_count: slot_value(ref, :db_select_count),
          insert_count: slot_value(ref, :db_insert_count),
          update_count: slot_value(ref, :db_update_count),
          delete_count: slot_value(ref, :db_delete_count),
          other_count: slot_value(ref, :db_other_count)
        },
        by_stage: %{
          resolve:
            db_stage_snapshot(
              ref,
              :db_resolve_query_count,
              :db_resolve_query_total_us
            ),
          runtime:
            db_stage_snapshot(
              ref,
              :db_runtime_query_count,
              :db_runtime_query_total_us
            ),
          persistence:
            db_stage_snapshot(
              ref,
              :db_persistence_query_count,
              :db_persistence_query_total_us
            )
        }
      },
      archive: archive_snapshot(mission_id)
    }
  end

  defp empty_snapshot(mission_id) do
    %{
      mission_id: mission_id,
      duration_sec: 0.0,
      ingress_count: 0,
      ingress_error_count: 0,
      raw_bytes_total: 0,
      packets: %{
        packet_count: 0,
        transfer_frame_count: 0,
        anomaly_count: 0
      },
      dispatch: %{
        dispatch_count: 0,
        work_item_count: 0,
        sample_count: 0
      },
      stages: %{
        resolve: %{count: 0, total_us: 0, avg_us: 0.0},
        runtime: %{count: 0, total_us: 0, avg_us: 0.0},
        persistence: %{count: 0, total_us: 0, avg_us: 0.0},
        end_to_end: %{count: 0, total_us: 0, avg_us: 0.0}
      },
      runtime_components: empty_runtime_component_snapshot(),
      db: %{
        query_count: 0,
        query_total_us: 0,
        query_avg_us: 0.0,
        queries_per_ingress: 0.0,
        query_time_per_ingress_us: 0.0,
        queue_total_us: 0,
        decode_total_us: 0,
        idle_total_us: 0,
        operations: %{
          select_count: 0,
          insert_count: 0,
          update_count: 0,
          delete_count: 0,
          other_count: 0
        },
        by_stage: %{
          resolve: %{query_count: 0, total_us: 0, avg_us: 0.0},
          runtime: %{query_count: 0, total_us: 0, avg_us: 0.0},
          persistence: %{query_count: 0, total_us: 0, avg_us: 0.0}
        }
      },
      archive: empty_archive_snapshot()
    }
  end

  defp stage_snapshot(ref, stage, count) when stage in @stages do
    total_key = String.to_atom("#{stage}_total_us")

    %{
      count: count,
      total_us: slot_value(ref, total_key),
      avg_us: average(slot_value(ref, total_key), count)
    }
  end

  defp db_stage_snapshot(ref, count_key, total_key) do
    count = slot_value(ref, count_key)
    total_us = slot_value(ref, total_key)

    %{
      query_count: count,
      total_us: total_us,
      avg_us: average(total_us, count)
    }
  end

  defp runtime_component_snapshot(ref) do
    Enum.into(@runtime_component_slot_pairs, %{}, fn {component, {count_key, total_key}} ->
      count = slot_value(ref, count_key)
      total_us = slot_value(ref, total_key)

      {component,
       %{
         count: count,
         total_us: total_us,
         avg_us: average(total_us, count)
       }}
    end)
  end

  defp empty_runtime_component_snapshot do
    Enum.into(@runtime_components, %{}, fn component ->
      {component, %{count: 0, total_us: 0, avg_us: 0.0}}
    end)
  end

  defp record_stage_timing(_ref, _stage, nil), do: :ok

  defp record_stage_timing(ref, stage, duration_us)
       when stage in @stages and is_integer(duration_us) do
    add(ref, String.to_atom("#{stage}_count"), 1)
    add(ref, String.to_atom("#{stage}_total_us"), duration_us)
  end

  defp record_stage_timing(_ref, _stage, _other), do: :ok

  defp record_stage_query(ref, :resolve, duration_us) do
    add(ref, :db_resolve_query_count, 1)
    add(ref, :db_resolve_query_total_us, duration_us)
  end

  defp record_stage_query(ref, :runtime, duration_us) do
    add(ref, :db_runtime_query_count, 1)
    add(ref, :db_runtime_query_total_us, duration_us)
  end

  defp record_stage_query(ref, :persistence, duration_us) do
    add(ref, :db_persistence_query_count, 1)
    add(ref, :db_persistence_query_total_us, duration_us)
  end

  defp record_stage_query(_ref, _stage, _duration_us), do: :ok

  defp record_runtime_component(mission_id, component, duration_us)
       when is_binary(mission_id) and component in @runtime_components and is_integer(duration_us) and
              duration_us >= 0 do
    ref = ensure_counter(mission_id)
    {count_key, total_key} = Map.fetch!(@runtime_component_slot_pairs, component)
    add(ref, count_key, 1)
    add(ref, total_key, duration_us)
    :ok
  end

  defp record_operation(ref, :select), do: add(ref, :db_select_count, 1)
  defp record_operation(ref, :insert), do: add(ref, :db_insert_count, 1)
  defp record_operation(ref, :update), do: add(ref, :db_update_count, 1)
  defp record_operation(ref, :delete), do: add(ref, :db_delete_count, 1)
  defp record_operation(ref, :other), do: add(ref, :db_other_count, 1)

  defp classify_operation(metadata) when is_map(metadata) do
    query =
      metadata
      |> Map.get(:query)
      |> query_to_binary()
      |> String.trim_leading()
      |> String.upcase()

    cond do
      String.starts_with?(query, "SELECT") -> :select
      String.starts_with?(query, "INSERT") -> :insert
      String.starts_with?(query, "UPDATE") -> :update
      String.starts_with?(query, "DELETE") -> :delete
      true -> :other
    end
  end

  defp classify_operation(_metadata), do: :other

  defp query_to_binary(nil), do: ""
  defp query_to_binary(query) when is_binary(query), do: query

  defp query_to_binary(query) do
    IO.iodata_to_binary(query)
  rescue
    _error -> ""
  end

  defp archive_snapshot(mission_id) when is_binary(mission_id) do
    ingress = IngressArchive.stats(mission_id)
    protocol = RecordArchive.stats(mission_id)

    %{
      ingress: ingress,
      protocol: protocol,
      combined: combine_archive_stats(ingress, protocol)
    }
  end

  defp empty_archive_snapshot do
    empty = empty_archive_stats()

    %{
      ingress: empty,
      protocol: empty,
      combined: empty
    }
  end

  defp empty_archive_stats do
    %{
      queue_depth: 0,
      oldest_buffered_age_ms: 0,
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      flushed_count: 0,
      segment_count: 0,
      flush_total_us: 0,
      avg_flush_us: 0.0,
      flushed_bytes_total: 0,
      avg_segment_bytes: 0.0
    }
  end

  defp combine_archive_stats(ingress, protocol) do
    flush_count = ingress.flush_count + protocol.flush_count
    segment_count = ingress.segment_count + protocol.segment_count
    flush_total_us = ingress.flush_total_us + protocol.flush_total_us
    flushed_bytes_total = ingress.flushed_bytes_total + protocol.flushed_bytes_total

    %{
      queue_depth: ingress.queue_depth + protocol.queue_depth,
      oldest_buffered_age_ms:
        max(ingress.oldest_buffered_age_ms, protocol.oldest_buffered_age_ms),
      flush_count: flush_count,
      flush_failure_count: ingress.flush_failure_count + protocol.flush_failure_count,
      last_flush_error: protocol.last_flush_error || ingress.last_flush_error,
      flushed_count: ingress.flushed_count + protocol.flushed_count,
      segment_count: segment_count,
      flush_total_us: flush_total_us,
      avg_flush_us: average(flush_total_us, flush_count),
      flushed_bytes_total: flushed_bytes_total,
      avg_segment_bytes: average(flushed_bytes_total, segment_count)
    }
  end

  defp telemetry_sample?(%Cadence.Telemetry.Sample{}), do: true
  defp telemetry_sample?(_output), do: false

  defp native_to_us(nil), do: 0

  defp native_to_us(value) when is_integer(value),
    do: System.convert_time_unit(value, :native, :microsecond)

  defp native_to_us(_value), do: 0

  defp elapsed_since_us(started_at) when is_integer(started_at),
    do: System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)

  defp slot_value(ref, key) do
    :counters.get(ref, Map.fetch!(@slots, key))
  end

  defp add(ref, key, value) when is_integer(value) and value >= 0 do
    :counters.add(ref, Map.fetch!(@slots, key), value)
  end

  defp add_optional(_ref, _key, nil), do: :ok
  defp add_optional(ref, key, value) when is_integer(value), do: add(ref, key, value)
  defp add_optional(_ref, _key, _value), do: :ok

  defp average(_total, 0), do: 0.0
  defp average(total, count) when is_integer(total) and is_integer(count), do: total / count

  defp restore_process_key(key, nil), do: Process.delete(key)
  defp restore_process_key(key, value), do: Process.put(key, value)
end
