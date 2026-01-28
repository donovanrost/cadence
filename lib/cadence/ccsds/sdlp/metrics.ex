defmodule Cadence.CCSDS.SDLP.Metrics do
  @moduledoc """
  Lightweight SDLP metrics using :counters keyed by scope + profile.
  """

  @table_name :cadence_sdlp_metrics

  @slots %{
    frame_decode_total: 1,
    frame_decode_ok: 2,
    frame_decode_drop: 3,
    frame_decode_error: 4,
    bytes_in: 5,
    frame_encode_total: 6,
    frame_encode_ok: 7,
    frame_encode_error: 8,
    bytes_out: 9,
    segmentation_calls: 10,
    segmentation_ok: 11,
    segmentation_error: 12,
    segments_emitted: 13,
    reassembly_calls: 14,
    reassembly_ok: 15,
    reassembly_error: 16,
    sdu_emitted: 17
  }

  @slot_count 18

  @type scope :: term()
  @type profile :: :tm | :aos | :uslp | :tc | term()

  def ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set,
          :named_table,
          :public,
          read_concurrency: true
        ])

      _ref ->
        :ok
    end
  end

  def scope_from_opts(opts) when is_list(opts) do
    Keyword.get(opts, :metrics_scope) || Keyword.get(opts, :metrics_key) ||
      Keyword.get(opts, :mission_id) || :global
  end

  def scope_from_ctx(ctx) when is_map(ctx) do
    Map.get(ctx, :metrics_scope) || Map.get(ctx, :metrics_key) || Map.get(ctx, :mission_id) ||
      :global
  end

  def inc(scope, profile, metric, amount \\ 1) do
    slot = Map.fetch!(@slots, metric)

    case ensure_counter(scope, profile) do
      nil -> :ok
      ref -> :counters.add(ref, slot, amount)
    end
  end

  def get_stats(scope) do
    ensure_table()

    @table_name
    |> :ets.match_object({{scope, :_}, :_})
    |> Enum.reduce(%{}, fn {{^scope, profile}, ref}, acc ->
      Map.put(acc, profile, build_stats(ref))
    end)
  end

  def cleanup(scope) do
    ensure_table()

    @table_name
    |> :ets.match_object({{scope, :_}, :_})
    |> Enum.each(fn {{^scope, profile}, _ref} ->
      :ets.delete(@table_name, {scope, profile})
    end)

    :ok
  end

  defp ensure_counter(scope, profile) do
    ensure_table()

    case :ets.lookup(@table_name, {scope, profile}) do
      [{_key, ref}] ->
        ref

      [] ->
        ref = :counters.new(@slot_count, [:write_concurrency])
        _ = :ets.insert_new(@table_name, {{scope, profile}, ref})

        case :ets.lookup(@table_name, {scope, profile}) do
          [{_key, stored_ref}] -> stored_ref
          [] -> nil
        end
    end
  end

  defp build_stats(ref) do
    %{
      frame_decode: %{
        total: :counters.get(ref, @slots.frame_decode_total),
        ok: :counters.get(ref, @slots.frame_decode_ok),
        drop: :counters.get(ref, @slots.frame_decode_drop),
        error: :counters.get(ref, @slots.frame_decode_error),
        bytes_in: :counters.get(ref, @slots.bytes_in)
      },
      frame_encode: %{
        total: :counters.get(ref, @slots.frame_encode_total),
        ok: :counters.get(ref, @slots.frame_encode_ok),
        error: :counters.get(ref, @slots.frame_encode_error),
        bytes_out: :counters.get(ref, @slots.bytes_out)
      },
      segmentation: %{
        calls: :counters.get(ref, @slots.segmentation_calls),
        ok: :counters.get(ref, @slots.segmentation_ok),
        error: :counters.get(ref, @slots.segmentation_error),
        segments_emitted: :counters.get(ref, @slots.segments_emitted)
      },
      reassembly: %{
        calls: :counters.get(ref, @slots.reassembly_calls),
        ok: :counters.get(ref, @slots.reassembly_ok),
        error: :counters.get(ref, @slots.reassembly_error),
        sdu_emitted: :counters.get(ref, @slots.sdu_emitted)
      }
    }
  end
end
