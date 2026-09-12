defmodule Cadence.Telemetry.Storage.QuestDB.PhysicalSampleReader do
  @moduledoc """
  Exact, tenant/source-scoped QuestDB observation lookup without effective selection.
  """

  alias Cadence.Telemetry.PhysicalSampleQuery
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, RestClient, SQL}

  @fields [
    organization_id: "organization_id",
    mission_id: "mission_id",
    point_id: "point_id",
    sample_id: "sample_id",
    realm: "realm",
    data_source_id: "data_source_id",
    source_binding_id: "binding_id",
    spacecraft_id: "spacecraft_id",
    replay_run_id: "replay_run_id"
  ]
  @times [
    receipt_time: "receipt_time =",
    from_receipt_time: "receipt_time >=",
    to_receipt_time: "receipt_time <=",
    from_observed_at: "observed_at >=",
    to_observed_at: "observed_at <="
  ]

  @spec fetch(PhysicalSampleQuery.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch(%PhysicalSampleQuery{} = query, opts) when is_list(opts) do
    with :ok <- PhysicalSampleQuery.validate(query),
         {:ok, sql} <- query_sql(query),
         {:ok, result} <- Keyword.get(opts, :exec_fun, &RestClient.exec/2).(sql, opts) do
      decode(result, query)
    end
  end

  @spec query_sql(PhysicalSampleQuery.t()) :: {:ok, binary()} | {:error, term()}
  def query_sql(%PhysicalSampleQuery{} = query) do
    with :ok <- PhysicalSampleQuery.validate(query) do
      clauses =
        Enum.flat_map(@fields, fn {key, column} ->
          clause("#{column} =", Map.fetch!(query, key))
        end) ++
          Enum.flat_map(@times, fn {key, operator} ->
            clause(operator, Map.fetch!(query, key))
          end) ++ endpoint_clause(query.source_endpoint_ids)

      {:ok,
       """
       SELECT #{Enum.join(columns(), ", ")}
       FROM telemetry_observations
       WHERE #{Enum.join(clauses, " AND ")}
       LIMIT 2
       """
       |> String.trim()}
    end
  end

  defp columns, do: ["organization_id" | ObservationReader.select_columns()]
  defp clause(_operator, nil), do: []
  defp clause(operator, value), do: ["#{operator} #{SQL.literal(value)}"]
  defp endpoint_clause(nil), do: []

  defp endpoint_clause(ids),
    do: ["source_endpoint_id IN (#{Enum.map_join(ids, ", ", &SQL.literal/1)})"]

  defp decode(%{"columns" => columns, "dataset" => rows}, query)
       when is_list(columns) and is_list(rows) and length(rows) <= 2 do
    names = Enum.map(columns, &Map.get(&1, "name"))

    if Enum.sort(names) == Enum.sort(columns()) and
         Enum.all?(rows, &(is_list(&1) and length(&1) == length(names))) do
      rows
      |> Enum.map(fn row -> names |> Enum.zip(row) |> Map.new() end)
      |> decode_rows(query)
    else
      {:error, :invalid_physical_sample_result}
    end
  rescue
    _ -> {:error, :invalid_physical_sample_result}
  end

  defp decode(_result, _query), do: {:error, :invalid_physical_sample_result}
  defp decode_rows([], _query), do: {:error, :not_found}

  defp decode_rows(rows, query) do
    if Enum.all?(rows, &valid_row?/1),
      do: admitted_records(rows, query),
      else: {:error, :invalid_physical_sample_result}
  end

  defp admitted_records(rows, query) do
    records =
      Enum.map(rows, fn row ->
        %{organization_id: row["organization_id"], sample: ObservationReader.sample_from_row(row)}
      end)

    cond do
      not Enum.all?(records, &PhysicalSampleQuery.matches?(query, &1.sample, &1.organization_id)) ->
        {:error, :physical_sample_context_mismatch}

      length(records) == 1 ->
        {:ok, hd(records)}

      true ->
        {:error, :ambiguous_physical_sample}
    end
  end

  # Physical inspection must not turn malformed clocks into receipt-time
  # fallbacks or unknown quality into an invented "suspect" measurement.
  defp valid_row?(row) do
    row["quality_state"] in ["good", "suspect", "bad"] and
      timestamp?(row["receipt_time"]) and
      (is_nil(row["generation_time"]) or timestamp?(row["generation_time"])) and
      valid_value?(row)
  end

  defp timestamp?(value) when is_binary(value),
    do: match?({:ok, _, _}, DateTime.from_iso8601(value))

  defp timestamp?(_value), do: false

  defp valid_value?(%{"value_kind" => "double", "value_double" => value}), do: is_number(value)
  defp valid_value?(%{"value_kind" => "long", "value_long" => value}), do: is_integer(value)
  defp valid_value?(%{"value_kind" => "bool", "value_bool" => value}), do: is_boolean(value)

  defp valid_value?(%{"value_kind" => kind, "value_string" => value})
       when kind in ["string", "term"],
       do: is_binary(value)

  defp valid_value?(%{"value_kind" => "nil"}), do: true
  defp valid_value?(_row), do: false
end
