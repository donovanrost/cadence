defmodule Cadence.Telemetry.DataManagement.HistoricalSourceSamples do
  @moduledoc false

  alias Cadence.Telemetry.HistoryStore

  def fetch(attrs) when is_map(attrs) do
    with {:ok, mission_id} <- required_attr(attrs, :mission_id),
         {:ok, point_id} <- point_id(attrs),
         {:ok, history_opts} <- history_opts(attrs),
         {:ok, %{samples: samples, diagnostics: diagnostics}} <-
           HistoryStore.sample_history_result(mission_id, point_id, history_opts) do
      {:ok, samples, source_diagnostics(attrs, point_id, history_opts, diagnostics)}
    end
  end

  def window_diagnostics(history_opts) when is_list(history_opts) do
    %{
      "from_observed_at" => diagnostic_text(Keyword.get(history_opts, :from_observed_at)),
      "to_observed_at" => diagnostic_text(Keyword.get(history_opts, :to_observed_at)),
      "from_receipt_time" => diagnostic_text(Keyword.get(history_opts, :from_receipt_time)),
      "to_receipt_time" => diagnostic_text(Keyword.get(history_opts, :to_receipt_time))
    }
  end

  def identity_diagnostics(attrs) when is_map(attrs) do
    %{
      "organization_id" => get_attr(attrs, :organization_id),
      "mission_id" => get_attr(attrs, :mission_id),
      "realm" => get_attr(attrs, :source_realm) || get_attr(attrs, :realm),
      "data_source_id" =>
        get_attr(attrs, :source_data_source_id) || get_attr(attrs, :data_source_id),
      "source_binding_id" => get_attr(attrs, :source_binding_id) || get_attr(attrs, :binding_id)
    }
  end

  defp source_diagnostics(attrs, point_id, history_opts, diagnostics) do
    %{
      "point_id" => point_id,
      "source_window" => window_diagnostics(history_opts),
      "source_identity" => identity_diagnostics(attrs),
      "history_diagnostics" => diagnostics
    }
  end

  defp point_id(attrs) do
    case get_attr(attrs, :point_id) || get_attr(attrs, :observable_id) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, :point_id}}
    end
  end

  defp history_opts(attrs) do
    with {:ok, from_observed_at} <- optional_datetime_attr(attrs, :source_from),
         {:ok, to_observed_at} <- optional_datetime_attr(attrs, :source_to),
         {:ok, from_receipt_time} <- optional_datetime_attr(attrs, :receipt_from),
         {:ok, to_receipt_time} <- optional_datetime_attr(attrs, :receipt_to) do
      [
        organization_id: get_attr(attrs, :organization_id),
        spacecraft_id: get_attr(attrs, :source_spacecraft_id) || get_attr(attrs, :spacecraft_id),
        realm: get_attr(attrs, :source_realm) || get_attr(attrs, :realm),
        replay_run_id: get_attr(attrs, :source_replay_run_id) || get_attr(attrs, :replay_run_id),
        data_source_id:
          get_attr(attrs, :source_data_source_id) || get_attr(attrs, :data_source_id),
        source_binding_id: get_attr(attrs, :source_binding_id) || get_attr(attrs, :binding_id),
        from_observed_at: from_observed_at,
        to_observed_at: to_observed_at,
        from_receipt_time: from_receipt_time,
        to_receipt_time: to_receipt_time,
        order: :asc,
        limit: history_limit(attrs)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> then(&{:ok, &1})
    end
  end

  defp history_limit(attrs) do
    case get_attr(attrs, :source_limit) || get_attr(attrs, :limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      limit when is_binary(limit) -> parse_positive_integer(limit, 10_000)
      _other -> 10_000
    end
  end

  defp required_attr(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp optional_datetime_attr(attrs, field) do
    case get_attr(attrs, field) do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      %DateTime{} = datetime ->
        {:ok, datetime}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, reason} -> {:error, {:invalid_datetime_field, field, value, reason}}
        end

      value ->
        {:error, {:invalid_datetime_field, field, value}}
    end
  end

  defp parse_positive_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp diagnostic_text(nil), do: nil
  defp diagnostic_text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp diagnostic_text(value) when is_binary(value), do: value
  defp diagnostic_text(value) when is_atom(value), do: Atom.to_string(value)
  defp diagnostic_text(value) when is_integer(value), do: Integer.to_string(value)
  defp diagnostic_text(value), do: inspect(value)

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
