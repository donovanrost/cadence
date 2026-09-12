defmodule Cadence.Reads.Dashboards.WorkspaceFrame do
  @moduledoc false
  alias Cadence.Dashboards.{Annotation, AnnotationSpan, Field, Frame}

  @max_values 10_000
  @max_fields 64
  @safe_integer 9_007_199_254_740_991

  # Browser frames deliberately exclude scope maps, credentials, evidence,
  # adapter diagnostics, raw actions and arbitrary metadata.
  def project(%Frame{} = frame) do
    with true <- frame.shape in Frame.shapes(),
         true <- is_nil(frame.time_axis) or frame.time_axis in Frame.time_axes(),
         true <- is_list(frame.fields) and length(frame.fields) <= @max_fields,
         {:ok, fields} <- collect(frame.fields, &field/1),
         true <- aligned?(fields) do
      {:ok,
       %{
         shape: Atom.to_string(frame.shape),
         time_axis: axis(frame.time_axis),
         fields: fields
       }}
    else
      _ -> {:error, :invalid_frame}
    end
  end

  def project(_), do: {:error, :invalid_frame}

  def annotation(%Annotation{span: %AnnotationSpan{} = span} = annotation) do
    if AnnotationSpan.valid?(span) and text?(annotation.annotation_id, 256) and
         text?(annotation.title, 4096) and annotation.severity in Annotation.severities() do
      {:ok,
       %{
         id: annotation.annotation_id,
         title: annotation.title,
         severity: Atom.to_string(annotation.severity),
         kind: Atom.to_string(span.kind),
         starts_at_ms: DateTime.to_unix(span.starts_at, :millisecond),
         ends_at_ms: if(span.ends_at, do: DateTime.to_unix(span.ends_at, :millisecond))
       }}
    else
      {:error, :invalid_annotation}
    end
  end

  def annotation(_), do: {:error, :invalid_annotation}

  defp field(%Field{name: name, kind: kind, values: values, metadata: metadata}) do
    with true <- text?(name, 256) and name != "" and kind in Field.kinds(),
         true <- is_list(values) and length(values) <= @max_values,
         {:ok, values} <- collect(values, &value(&1, kind)),
         unit = if(is_map(metadata), do: Map.get(metadata, :unit, Map.get(metadata, "unit"))),
         true <- is_nil(unit) or text?(unit, 128) do
      {:ok, %{name: name, kind: Atom.to_string(kind), unit: unit, values: values}}
    else
      _ -> {:error, :invalid_field}
    end
  end

  defp field(_), do: {:error, :invalid_field}
  defp value(nil, _), do: {:ok, nil}
  defp value(%DateTime{} = value, :time), do: value(DateTime.to_unix(value, :millisecond), :time)

  defp value(value, :time) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} -> value(time, :time)
      _ -> {:error, :invalid_time}
    end
  end

  defp value(value, kind)
       when kind in [:time, :number] and is_integer(value) and abs(value) <= @safe_integer,
       do: {:ok, value}

  defp value(value, :number) when is_float(value) and abs(value) <= @safe_integer,
    do: {:ok, value}

  defp value(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp value(value, kind) when kind in [:string, :enum] and is_binary(value) do
    if text?(value, 4096), do: {:ok, value}, else: {:error, :invalid_text}
  end

  defp value(value, :enum) when is_atom(value), do: {:ok, Atom.to_string(value)}
  defp value(_value, _kind), do: {:error, :invalid_value}

  defp axis(axis) when axis in [:generation_time, :receipt_time, :occurred_at],
    do: Atom.to_string(axis)

  defp axis(_), do: nil

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value)

  defp aligned?(fields) do
    names = Enum.map(fields, & &1.name)

    length(Enum.uniq(names)) == length(names) and
      length(Enum.uniq(Enum.map(fields, &length(&1.values)))) <= 1
  end

  defp collect(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
