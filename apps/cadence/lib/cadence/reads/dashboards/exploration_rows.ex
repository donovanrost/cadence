defmodule Cadence.Reads.Dashboards.ExplorationRows do
  @moduledoc false
  alias Cadence.Dashboards.{Field, Frame}
  alias Cadence.Reads.Dashboards.WorkspaceFrame

  def project(frames, request) when is_list(frames) and length(frames) <= 64 do
    limit = request.interaction_context.source_query.max_raw_points
    order = request.interaction_context.source_query.order
    [placement] = request.document.placements
    [point] = placement.widget_def.binding.observables

    with true <- Enum.reduce(frames, 0, &(row_count(&1) + &2)) <= 64 * limit,
         {:ok, batches} <- collect(frames, &frame(&1, point, limit)),
         rows = Enum.flat_map(batches, & &1.rows),
         true <- length(Enum.uniq_by(rows, & &1.key)) == length(rows) do
      limited = length(rows) >= limit or Enum.any?(batches, & &1.limited)

      rows =
        rows
        |> Enum.sort_by(&sort_key/1, order)
        |> Enum.take(limit)

      {:ok, rows, limited}
    else
      _ -> :error
    end
  end

  def project(_, _), do: :error

  defp frame(%Frame{source: :telemetry, fields: [time, value]} = frame, point, limit) do
    with %Field{kind: :time, name: "time", values: times} <- time,
         %Field{name: ^point, metadata: metadata} <- value,
         true <- length(times) <= frame_bound(frame.meta, limit),
         true <- length(value.values) == length(times),
         {:ok, sources} <- row_sources(frame.meta, length(times), limit),
         {:ok, safe_value} <- safe_value(frame),
         {:ok, times} <- collect(times, &timestamp/1),
         ids when is_list(ids) and length(ids) == length(times) <- metadata[:sample_ids],
         true <- Enum.all?(ids, &optional_identity?/1),
         true <- text?(frame.frame_id, 1024),
         true <- frame.time_axis in [:generation_time, :receipt_time] do
      rows =
        Enum.zip([times, safe_value.values, ids, sources])
        |> Enum.with_index()
        |> Enum.map(fn {{time, value, sample, source}, index} ->
          %{
            key: key(frame.frame_id, index),
            point_id: point,
            sample_id: sample,
            time: time,
            axis: Atom.to_string(frame.time_axis),
            value: value,
            value_kind: safe_value.kind,
            unit: safe_value.unit,
            source: source
          }
        end)

      {:ok, %{rows: rows, limited: Map.get(frame.meta, :truncated?, false) == true}}
    else
      _ -> :error
    end
  end

  defp frame(_, _, _), do: :error

  defp row_count(%Frame{fields: [%Field{values: values} | _]}) when is_list(values),
    do: length(values)

  defp row_count(_), do: 64_001
  defp frame_bound(%{segmented_source_bindings?: true}, limit), do: 64 * limit
  defp frame_bound(_, limit), do: limit

  # A merged source may contain up to one bounded batch per historical segment.
  # Validate in bounded chunks before globally ordering and taking the UI limit.
  defp safe_value(%Frame{fields: [time, value]} = frame) do
    batches =
      if value.values == [] do
        [frame]
      else
        Enum.zip(Enum.chunk_every(time.values, 1000), Enum.chunk_every(value.values, 1000))
        |> Enum.map(fn {times, values} ->
          %{frame | fields: [%{time | values: times}, %{value | values: values}]}
        end)
      end

    with {:ok, projected} <- collect(batches, &WorkspaceFrame.project/1) do
      values = Enum.map(projected, fn %{fields: [_, value]} -> value end)
      [first | _] = values
      {:ok, %{first | values: Enum.flat_map(values, & &1.values)}}
    end
  end

  defp row_sources(%{segmented_source_bindings?: true} = meta, count, limit) do
    with spans when is_list(spans) and length(spans) <= 64 <- meta[:source_binding_row_spans],
         {:ok, sources} <- collect(spans, &source_span(&1, limit)),
         sources = List.flatten(sources),
         true <- length(sources) == count do
      {:ok, sources}
    else
      _ -> :error
    end
  end

  defp row_sources(meta, count, _limit) do
    with {:ok, source} <- source(meta), do: {:ok, List.duplicate(source, count)}
  end

  defp source_span(%{count: count, source: metadata} = span, total)
       when map_size(span) == 2 and is_integer(count) and count >= 0 and count <= total do
    with {:ok, source} <- source(metadata), do: {:ok, List.duplicate(source, count)}
  end

  defp source_span(_, _), do: :error

  defp source(meta) when is_map(meta) do
    source = Map.take(meta, [:data_source_id, :source_binding_id, :dataset, :realm])
    realm = Map.get(source, :realm)

    if Enum.all?([:data_source_id, :source_binding_id, :dataset], &optional_identity?(source[&1])) and
         realm in [
           :flight,
           :rehearsal,
           :replay,
           :simulation,
           "flight",
           "rehearsal",
           "replay",
           "simulation"
         ] do
      {:ok,
       %{
         data_source_id: source[:data_source_id],
         source_binding_id: source[:source_binding_id],
         dataset: source[:dataset],
         realm: to_string(realm)
       }}
    else
      :error
    end
  end

  defp source(_), do: :error
  defp sort_key(%{time: nil, key: key}), do: {0, 0, key}

  defp sort_key(%{time: time, key: key}) do
    {:ok, time, _} = DateTime.from_iso8601(time)
    {1, DateTime.to_unix(time, :microsecond), key}
  end

  defp timestamp(nil), do: {:ok, nil}
  defp timestamp(%DateTime{} = time), do: {:ok, DateTime.to_iso8601(time)}

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} -> timestamp(time)
      _ -> :error
    end
  end

  defp timestamp(_), do: :error
  defp optional_identity?(nil), do: true
  defp optional_identity?(value), do: identity?(value)

  defp identity?(value), do: text?(value, 256)

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and String.valid?(value)

  defp key(frame, index),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary({frame, index})) |> Base.encode16(case: :lower)

  defp collect(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, projected} -> {:cont, {:ok, [projected | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      _ -> :error
    end
  end
end
