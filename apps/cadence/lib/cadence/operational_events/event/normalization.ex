defmodule Cadence.OperationalEvents.Event.Normalization do
  @moduledoc false

  def fetch_required(attrs, key) when is_map(attrs) and is_atom(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(attrs, Atom.to_string(key))
    end
  end

  def scoped_event_id(source_record_kind, source_record_id, replay_run_id)
      when is_binary(replay_run_id) and replay_run_id != "" do
    "operational_event:#{source_record_kind}:#{replay_run_id}:#{source_record_id}"
  end

  def scoped_event_id(source_record_kind, source_record_id, _replay_run_id) do
    "operational_event:#{source_record_kind}:#{source_record_id}"
  end

  def normalize_known_required(map, key, known, label) do
    case fetch_map_value(map, key) do
      {:ok, value} -> put_normalized_value(map, key, known_atom!(value, known, label))
      :error -> raise KeyError, key: key, term: map
    end
  end

  def normalize_known_optional(map, key, known, label) do
    case fetch_map_value(map, key) do
      {:ok, nil} -> Map.delete(map, key)
      {:ok, value} -> put_normalized_value(map, key, known_atom!(value, known, label))
      :error -> map
    end
  end

  def normalize_text_required(map, key) do
    case fetch_map_value(map, key) do
      {:ok, value} -> put_normalized_value(map, key, text_value!(value))
      :error -> raise KeyError, key: key, term: map
    end
  end

  def normalize_text_optional(map, key) do
    case fetch_map_value(map, key) do
      {:ok, nil} -> Map.delete(map, key)
      {:ok, value} -> put_normalized_value(map, key, text_value(value))
      :error -> map
    end
  end

  def known_optional_atom!(nil, _known, _label), do: nil
  def known_optional_atom!(value, known, label), do: known_atom!(value, known, label)

  def known_atom!(value, known, label) when is_atom(value) do
    if value in known,
      do: value,
      else: raise(ArgumentError, "unsupported #{label}: #{inspect(value)}")
  end

  def known_atom!(value, known, label) when is_binary(value) do
    Enum.find(known, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{label}: #{inspect(value)}"
  end

  def known_atom!(value, _known, label),
    do: raise(ArgumentError, "unsupported #{label}: #{inspect(value)}")

  def normalize_kind(value) when is_atom(value), do: value
  def normalize_kind(value) when is_binary(value), do: String.to_existing_atom(value)

  def map_value(value) when is_map(value), do: value

  def map_value(_value), do: %{}

  def fetch_map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, Atom.to_string(key))
    end
  end

  def put_normalized_value(map, key, value) when is_map(map) and is_atom(key) do
    map
    |> Map.delete(Atom.to_string(key))
    |> Map.put(key, value)
  end

  def text_value(nil), do: nil
  def text_value(value) when is_binary(value), do: value
  def text_value(value) when is_atom(value), do: Atom.to_string(value)

  def text_value!(value) do
    case text_value(value) do
      nil -> raise ArgumentError, "expected text value, got nil"
      value -> value
    end
  end

  def compact(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}, []] end)
    |> Map.new()
  end
end
