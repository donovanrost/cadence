defmodule Cadence.Telemetry.Storage.QuestDB.ObservationReader do
  @moduledoc """
  Reads Cadence telemetry observations from QuestDB.

  The reader returns `Cadence.Telemetry.Sample` for compatibility with the
  existing history APIs. Richer dashboard frame reads can build on the same
  query shape later.
  """

  import Ecto.Query

  alias Cadence.Persistence.Schemas.TelemetryObservationIdentityStateRow
  alias Cadence.Repo
  alias Cadence.Telemetry.{EffectiveSelection, Sample, SelectionPolicy, SourceFilters}
  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SQL}

  @select_columns [
    "sample_id",
    "mission_id",
    "spacecraft_id",
    "point_id",
    "point_name",
    "packet_definition_id",
    "packet_definition_version",
    "packet_id",
    "evidence_id",
    "value_kind",
    "value_double",
    "value_long",
    "value_bool",
    "value_string",
    "raw_value_text",
    "quality_state",
    "generation_time",
    "receipt_time",
    "provenance_json",
    "realm",
    "data_source_id",
    "binding_id",
    "source_endpoint_id",
    "replay_run_id",
    "observation_id",
    "observation_identity_id",
    "validity_state"
  ]

  @decimated_select_columns [
    "bucket_start",
    "bucket_min",
    "bucket_max",
    "bucket_mean",
    "sample_count",
    "worst_quality_state"
  ]

  @watermark_select_columns [
    "latest_receipt_time",
    "retention_starts_at",
    "sample_count"
  ]

  @spec select_columns() :: [binary()]
  def select_columns, do: @select_columns

  @spec decimated_select_columns() :: [binary()]
  def decimated_select_columns, do: @decimated_select_columns

  @spec watermark_select_columns() :: [binary()]
  def watermark_select_columns, do: @watermark_select_columns

  @spec sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    case sample_history_result(mission_id, point_id, opts) do
      {:ok, %{samples: samples}} -> samples
      {:error, _reason} -> []
    end
  end

  @spec sample_history_result(binary(), binary(), keyword()) ::
          {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  def sample_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    with :ok <- validate_read_context(opts),
         sql <- query_sql(mission_id, point_id, opts),
         {:ok, result} <- exec(sql, opts) do
      physical_samples = samples_from_result(result)

      samples =
        physical_samples
        |> EffectiveSelection.selected_samples(
          identity_states_for_point(mission_id, point_id, opts),
          opts
        )
        |> Enum.take(limit(opts))

      {:ok,
       %{
         samples: samples,
         diagnostics: sample_history_diagnostics(physical_samples, samples, opts)
       }}
    end
  end

  @spec decimated_history(binary(), binary(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def decimated_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    case decimated_history_result(mission_id, point_id, opts) do
      {:ok, %{buckets: buckets}} -> {:ok, buckets}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec decimated_history_result(binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    bucket_width_ms = bucket_width_ms(opts)

    with :ok <- validate_read_context(opts),
         sql <- decimated_query_sql(mission_id, point_id, opts),
         {:ok, result} <- exec(sql, opts) do
      buckets = decimated_buckets_from_result(result, bucket_width_ms)

      {:ok,
       %{
         buckets: buckets,
         diagnostics: decimated_history_diagnostics(buckets, opts)
       }}
    end
  end

  @spec sample_watermark_result(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def sample_watermark_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    with :ok <- validate_read_context(opts),
         sql <- watermark_query_sql(mission_id, point_id, opts),
         {:ok, result} <- exec(sql, opts) do
      {:ok, watermark_from_result(result)}
    end
  end

  @spec query(binary(), binary(), keyword()) :: {binary(), [term()]}
  def query(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    filters = [
      {"mission_id = ?", mission_id},
      {"point_id = ?", point_id},
      {"realm = ?", symbol_opt(opts, :realm, :flight)}
    ]

    filters =
      filters
      |> maybe_filter("validity_state = ?", sample_history_validity_state_filter(opts))
      |> maybe_filter("organization_id = ?", Keyword.get(opts, :organization_id))
      |> maybe_filter("spacecraft_id = ?", Keyword.get(opts, :spacecraft_id))
      |> maybe_filter("data_source_id = ?", Keyword.get(opts, :data_source_id))
      |> maybe_filter("binding_id = ?", SourceFilters.binding_id(opts))
      |> maybe_filter("replay_run_id = ?", SourceFilters.replay_run_id(opts))
      |> maybe_filter_source_endpoints(opts)
      |> maybe_filter("receipt_time >= ?", timestamp_opt(opts, :from_receipt_time))
      |> maybe_filter("receipt_time <= ?", timestamp_opt(opts, :to_receipt_time))
      |> maybe_filter("observed_at >= ?", timestamp_opt(opts, :from_observed_at))
      |> maybe_filter("observed_at <= ?", timestamp_opt(opts, :to_observed_at))

    {where_sql, params} = where_sql_and_params(filters)

    limit = query_limit(opts)
    order = order(opts)
    order_clause = order_clause(opts, order)

    sql = """
    SELECT #{Enum.join(@select_columns, ", ")}
    FROM telemetry_observations
    WHERE #{where_sql}
    ORDER BY #{order_clause}
    LIMIT #{limit}
    """

    {String.trim(sql), params}
  end

  @spec query_sql(binary(), binary(), keyword()) :: binary()
  def query_sql(mission_id, point_id, opts \\ []) do
    {sql, params} = query(mission_id, point_id, opts)

    render_sql(sql, params)
  end

  @spec decimated_query(binary(), binary(), keyword()) :: {binary(), [term()]}
  def decimated_query(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    filters = [
      {"mission_id = ?", mission_id},
      {"point_id = ?", point_id},
      {"realm = ?", symbol_opt(opts, :realm, :flight)}
    ]

    filters =
      filters
      |> maybe_filter("validity_state = ?", validity_state_filter(opts))
      |> maybe_filter("organization_id = ?", Keyword.get(opts, :organization_id))
      |> maybe_filter("spacecraft_id = ?", Keyword.get(opts, :spacecraft_id))
      |> maybe_filter("data_source_id = ?", Keyword.get(opts, :data_source_id))
      |> maybe_filter("binding_id = ?", SourceFilters.binding_id(opts))
      |> maybe_filter("replay_run_id = ?", SourceFilters.replay_run_id(opts))
      |> maybe_filter_source_endpoints(opts)
      |> maybe_filter("receipt_time >= ?", timestamp_opt(opts, :from_receipt_time))
      |> maybe_filter("receipt_time <= ?", timestamp_opt(opts, :to_receipt_time))
      |> maybe_filter("observed_at >= ?", timestamp_opt(opts, :from_observed_at))
      |> maybe_filter("observed_at <= ?", timestamp_opt(opts, :to_observed_at))

    {where_sql, params} = where_sql_and_params(filters, ["value_kind IN ('double', 'long')"])

    bucket = sample_by_bucket(opts)

    sql = """
    SELECT
      observed_at AS bucket_start,
      min(coalesce(value_double, value_long)) AS bucket_min,
      max(coalesce(value_double, value_long)) AS bucket_max,
      avg(coalesce(value_double, value_long)) AS bucket_mean,
      count() AS sample_count,
      first(quality_state) AS worst_quality_state
    FROM telemetry_observations
    WHERE #{where_sql}
    SAMPLE BY #{bucket} ALIGN TO CALENDAR
    """

    {String.trim(sql), params}
  end

  @spec decimated_query_sql(binary(), binary(), keyword()) :: binary()
  def decimated_query_sql(mission_id, point_id, opts \\ []) do
    {sql, params} = decimated_query(mission_id, point_id, opts)

    render_sql(sql, params)
  end

  @spec watermark_query(binary(), binary(), keyword()) :: {binary(), [term()]}
  def watermark_query(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    filters = [
      {"mission_id = ?", mission_id},
      {"point_id = ?", point_id},
      {"realm = ?", symbol_opt(opts, :realm, :flight)}
    ]

    filters =
      filters
      |> maybe_filter("validity_state = ?", validity_state_filter(opts))
      |> maybe_filter("organization_id = ?", Keyword.get(opts, :organization_id))
      |> maybe_filter("spacecraft_id = ?", Keyword.get(opts, :spacecraft_id))
      |> maybe_filter("data_source_id = ?", Keyword.get(opts, :data_source_id))
      |> maybe_filter("binding_id = ?", SourceFilters.binding_id(opts))
      |> maybe_filter("replay_run_id = ?", SourceFilters.replay_run_id(opts))
      |> maybe_filter_source_endpoints(opts)

    {where_sql, params} = where_sql_and_params(filters)

    sql = """
    SELECT
      max(receipt_time) AS latest_receipt_time,
      min(receipt_time) AS retention_starts_at,
      count() AS sample_count
    FROM telemetry_observations
    WHERE #{where_sql}
    """

    {String.trim(sql), params}
  end

  @spec watermark_query_sql(binary(), binary(), keyword()) :: binary()
  def watermark_query_sql(mission_id, point_id, opts \\ []) do
    {sql, params} = watermark_query(mission_id, point_id, opts)

    render_sql(sql, params)
  end

  @spec samples_from_result(map()) :: [Sample.t()]
  def samples_from_result(%{"columns" => columns, "dataset" => rows}) do
    column_names = Enum.map(columns, & &1["name"])

    Enum.map(rows, fn row ->
      column_names
      |> Enum.zip(row)
      |> Map.new()
      |> sample_from_row()
    end)
  end

  @spec decimated_buckets_from_result(map(), pos_integer()) :: [map()]
  def decimated_buckets_from_result(%{"columns" => columns, "dataset" => rows}, bucket_width_ms)
      when is_integer(bucket_width_ms) and bucket_width_ms > 0 do
    column_names = Enum.map(columns, & &1["name"])

    Enum.map(rows, fn row ->
      row =
        column_names
        |> Enum.zip(row)
        |> Map.new()

      bucket_start = utc_datetime(get(row, "bucket_start"))

      %{
        bucket_start: bucket_start,
        bucket_end: bucket_end(bucket_start, bucket_width_ms),
        min: get(row, "bucket_min"),
        max: get(row, "bucket_max"),
        mean: get(row, "bucket_mean"),
        sample_count: get(row, "sample_count"),
        worst_quality_state: quality_state(get(row, "worst_quality_state"))
      }
    end)
  end

  @spec watermark_from_result(map()) :: map()
  def watermark_from_result(%{"columns" => columns, "dataset" => rows}) do
    column_names = Enum.map(columns, & &1["name"])

    row =
      rows
      |> List.first([])
      |> then(fn row -> column_names |> Enum.zip(row) |> Map.new() end)

    latest_receipt_time = utc_datetime(get(row, "latest_receipt_time"))
    sample_count = get(row, "sample_count") || 0

    %{
      complete_through: latest_receipt_time,
      latest_receipt_time: latest_receipt_time,
      retention_starts_at: utc_datetime(get(row, "retention_starts_at")),
      sample_count: sample_count,
      confidence: watermark_confidence(latest_receipt_time, sample_count)
    }
  end

  @spec sample_from_row(map()) :: Sample.t()
  def sample_from_row(row) when is_map(row) do
    storage_metadata = %{
      "realm" => get(row, "realm"),
      "data_source_id" => get(row, "data_source_id"),
      "binding_id" => get(row, "binding_id"),
      "source_endpoint_id" => get(row, "source_endpoint_id"),
      "replay_run_id" => get(row, "replay_run_id"),
      "observation_id" => get(row, "observation_id"),
      "observation_identity_id" => get(row, "observation_identity_id"),
      "validity_state" => get(row, "validity_state")
    }

    %Sample{
      sample_id: get(row, "sample_id"),
      mission_id: get(row, "mission_id"),
      spacecraft_id: get(row, "spacecraft_id"),
      point_id: get(row, "point_id"),
      point_name: get(row, "point_name"),
      packet_definition_id: get(row, "packet_definition_id"),
      packet_definition_version: get(row, "packet_definition_version"),
      packet_id: get(row, "packet_id"),
      evidence_id: get(row, "evidence_id"),
      raw_value: decode_raw_value(get(row, "raw_value_text")),
      engineering_value: engineering_value(row),
      quality_state: quality_state(get(row, "quality_state")),
      generation_time: utc_datetime(get(row, "generation_time")),
      receipt_time: utc_datetime(get(row, "receipt_time")),
      provenance:
        row
        |> get("provenance_json")
        |> decode_json_map()
        |> Map.put("storage", storage_metadata)
    }
  end

  defp maybe_filter(filters, _sql, nil), do: filters
  defp maybe_filter(filters, _sql, ""), do: filters
  defp maybe_filter(filters, sql, value), do: filters ++ [{sql, value}]

  defp maybe_filter_source_endpoints(filters, opts) do
    opts
    |> SourceFilters.normalize()
    |> Map.get(:source_endpoint_ids, [])
    |> case do
      [] ->
        filters

      [source_endpoint_id] ->
        maybe_filter(filters, "source_endpoint_id = ?", source_endpoint_id)

      source_endpoint_ids ->
        sql =
          source_endpoint_ids
          |> Enum.map_join(" OR ", fn _source_endpoint_id -> "source_endpoint_id = ?" end)
          |> then(&("(" <> &1 <> ")"))

        filters ++ [{sql, source_endpoint_ids}]
    end
  end

  defp where_sql_and_params(filters, extra_clauses \\ []) do
    {clauses, params, _index} =
      Enum.reduce(filters, {[], [], 1}, fn {sql, value}, {clauses, params, index} ->
        values = List.wrap(value)
        {clause, next_index} = parameterize_clause(sql, index, length(values))

        {clauses ++ [clause], params ++ values, next_index}
      end)

    {(clauses ++ extra_clauses) |> Enum.join(" AND "), params}
  end

  defp parameterize_clause(sql, index, count) do
    Enum.reduce(0..(count - 1)//1, {sql, index}, fn _offset, {clause, current_index} ->
      {String.replace(clause, "?", "$#{current_index}", global: false), current_index + 1}
    end)
  end

  defp render_sql(sql, params) do
    params
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.reduce(sql, fn {param, index}, acc ->
      String.replace(acc, "$#{index}", SQL.literal(param))
    end)
  end

  defp exec(sql, opts) do
    exec_fun = Keyword.get(opts, :exec_fun, &RestClient.exec/2)
    exec_fun.(sql, opts)
  end

  defp validate_read_context(opts) do
    if replay_realm?(Keyword.get(opts, :realm)) and is_nil(SourceFilters.replay_run_id(opts)) do
      {:error, {:missing_field, :replay_run_id}}
    else
      :ok
    end
  end

  defp replay_realm?(:replay), do: true
  defp replay_realm?("replay"), do: true
  defp replay_realm?(_realm), do: false

  defp identity_states_for_point(mission_id, point_id, opts) do
    case Keyword.fetch(opts, :identity_states) do
      {:ok, identity_states} when is_list(identity_states) ->
        identity_states

      {:ok, nil} ->
        []

      :error ->
        query_identity_states(mission_id, point_id, opts)
    end
  end

  defp query_identity_states(mission_id, point_id, opts) do
    TelemetryObservationIdentityStateRow
    |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
    |> maybe_filter_organization(Keyword.get(opts, :organization_id))
    |> maybe_filter_spacecraft(Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_realm(Keyword.get(opts, :realm))
    |> maybe_filter_replay_run(SourceFilters.replay_run_id(opts))
    |> maybe_filter_data_source(Keyword.get(opts, :data_source_id))
    |> maybe_filter_binding(SourceFilters.binding_id(opts))
    |> Repo.all()
  end

  defp maybe_filter_organization(query, nil), do: query

  defp maybe_filter_organization(query, organization_id) do
    where(query, [row], row.organization_id == ^organization_id)
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id) do
    where(query, [row], row.spacecraft_id == ^spacecraft_id)
  end

  defp maybe_filter_realm(query, nil), do: query
  defp maybe_filter_realm(query, ""), do: query

  defp maybe_filter_realm(query, realm) do
    realm = to_string(realm)
    where(query, [row], row.realm == ^realm)
  end

  defp maybe_filter_replay_run(query, nil), do: query
  defp maybe_filter_replay_run(query, ""), do: query

  defp maybe_filter_replay_run(query, replay_run_id) do
    where(query, [row], row.replay_run_id == ^replay_run_id)
  end

  defp maybe_filter_data_source(query, nil), do: query
  defp maybe_filter_data_source(query, ""), do: query

  defp maybe_filter_data_source(query, data_source_id) do
    where(query, [row], row.data_source_id == ^data_source_id)
  end

  defp maybe_filter_binding(query, nil), do: query
  defp maybe_filter_binding(query, ""), do: query

  defp maybe_filter_binding(query, binding_id) do
    where(query, [row], row.binding_id == ^binding_id)
  end

  defp symbol_opt(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
      _other -> Atom.to_string(default)
    end
  end

  defp validity_state_filter(opts) do
    case SelectionPolicy.validity_state_filter(opts) do
      nil -> nil
      state -> Atom.to_string(state)
    end
  end

  defp sample_history_validity_state_filter(opts) do
    case SelectionPolicy.validity_state_filter(opts) do
      :canonical -> nil
      nil -> nil
      state -> Atom.to_string(state)
    end
  end

  defp timestamp_opt(opts, key) do
    opts
    |> Keyword.get(key)
    |> timestamp_param()
  end

  defp timestamp_param(nil), do: nil

  defp timestamp_param(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
  end

  defp timestamp_param(%NaiveDateTime{} = datetime), do: datetime

  defp order(opts) do
    case Keyword.get(opts, :order, :desc) do
      :asc -> "ASC"
      "asc" -> "ASC"
      _other -> "DESC"
    end
  end

  defp order_clause(opts, order) do
    case Keyword.get(opts, :time_axis) do
      :generation_time -> "observed_at #{order}, receipt_time #{order}, sample_id #{order}"
      "generation_time" -> "observed_at #{order}, receipt_time #{order}, sample_id #{order}"
      _axis -> "receipt_time #{order}, sample_id #{order}"
    end
  end

  defp limit(opts) do
    case Keyword.get(opts, :limit, 100) do
      limit when is_integer(limit) and limit > 0 -> min(limit, 10_000)
      _other -> 100
    end
  end

  defp query_limit(opts) do
    if effective_canonical_sample_history?(opts) do
      candidate_limit(opts)
    else
      limit(opts)
    end
  end

  defp candidate_limit(opts) do
    explicit_candidate_limit =
      Keyword.get(opts, :candidate_limit) || Keyword.get(opts, :physical_candidate_limit)

    case explicit_candidate_limit do
      limit when is_integer(limit) and limit > 0 ->
        min(limit, 10_000)

      _other ->
        opts
        |> limit()
        |> Kernel.*(10)
        |> max(100)
        |> min(10_000)
    end
  end

  defp effective_canonical_sample_history?(opts) do
    SelectionPolicy.validity_state_filter(opts) == :canonical
  end

  defp sample_history_diagnostics(physical_samples, selected_samples, opts) do
    requested_logical_limit = limit(opts)
    physical_candidate_limit = query_limit(opts)
    physical_candidate_count = length(physical_samples)
    logical_selected_count = length(selected_samples)

    %{
      effective_selection?: effective_canonical_sample_history?(opts),
      physical_candidate_count: physical_candidate_count,
      logical_selected_count: logical_selected_count,
      requested_logical_limit: requested_logical_limit,
      physical_candidate_limit: physical_candidate_limit,
      candidate_window_exhausted?:
        effective_canonical_sample_history?(opts) and
          physical_candidate_count >= physical_candidate_limit and
          logical_selected_count < requested_logical_limit
    }
  end

  defp decimated_history_diagnostics(buckets, opts) do
    %{
      canonical_mode: :physical,
      aggregate_semantics: :physical_as_recorded,
      bucket_count: length(buckets),
      bucket_width_ms: bucket_width_ms(opts),
      target_points: Keyword.get(opts, :target_points),
      effective_selection?: false
    }
  end

  defp bucket_width_ms(opts) do
    case Keyword.get(opts, :bucket_width_ms) do
      width when is_integer(width) and width > 0 ->
        width

      _other ->
        inferred_bucket_width_ms(opts)
    end
  end

  defp inferred_bucket_width_ms(opts) do
    with target when is_integer(target) and target > 0 <- Keyword.get(opts, :target_points),
         %NaiveDateTime{} = from_time <- timestamp_opt(opts, :from_receipt_time),
         %NaiveDateTime{} = to_time <- timestamp_opt(opts, :to_receipt_time),
         diff_us when diff_us > 0 <- NaiveDateTime.diff(to_time, from_time, :microsecond) do
      diff_us
      |> div(1_000)
      |> div(target)
      |> max(1)
    else
      _other -> 60_000
    end
  end

  defp sample_by_bucket(opts) do
    "#{bucket_width_ms(opts)}ms"
  end

  defp bucket_end(nil, _bucket_width_ms), do: nil

  defp bucket_end(%DateTime{} = bucket_start, bucket_width_ms) do
    DateTime.add(bucket_start, bucket_width_ms, :millisecond)
  end

  defp watermark_confidence(%DateTime{}, sample_count) when sample_count > 0, do: :best_effort
  defp watermark_confidence(_latest_receipt_time, _sample_count), do: :unknown

  defp engineering_value(row) do
    case get(row, "value_kind") do
      "double" -> get(row, "value_double")
      "long" -> get(row, "value_long")
      "bool" -> get(row, "value_bool")
      "string" -> get(row, "value_string")
      "nil" -> nil
      "term" -> decode_raw_value(get(row, "value_string"))
      _other -> get(row, "value_string")
    end
  end

  defp decode_raw_value(nil), do: nil

  defp decode_raw_value(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> value
    end
  end

  defp decode_raw_value(value), do: value

  defp decode_json_map(nil), do: %{}

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(_value), do: %{}

  defp quality_state("good"), do: :good
  defp quality_state("bad"), do: :bad
  defp quality_state("suspect"), do: :suspect
  defp quality_state(_other), do: :suspect

  defp utc_datetime(nil), do: nil

  defp utc_datetime(%DateTime{} = datetime) do
    DateTime.shift_zone!(datetime, "Etc/UTC")
  end

  defp utc_datetime(%NaiveDateTime{} = datetime) do
    DateTime.from_naive!(datetime, "Etc/UTC")
  end

  defp utc_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        DateTime.shift_zone!(datetime, "Etc/UTC")

      {:error, _reason} ->
        value
        |> NaiveDateTime.from_iso8601!()
        |> DateTime.from_naive!("Etc/UTC")
    end
  end

  defp get(row, key) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.get(row, key_atom(key))
    end
  end

  defp key_atom("sample_id"), do: :sample_id
  defp key_atom("mission_id"), do: :mission_id
  defp key_atom("spacecraft_id"), do: :spacecraft_id
  defp key_atom("point_id"), do: :point_id
  defp key_atom("point_name"), do: :point_name
  defp key_atom("packet_definition_id"), do: :packet_definition_id
  defp key_atom("packet_definition_version"), do: :packet_definition_version
  defp key_atom("packet_id"), do: :packet_id
  defp key_atom("evidence_id"), do: :evidence_id
  defp key_atom("value_kind"), do: :value_kind
  defp key_atom("value_double"), do: :value_double
  defp key_atom("value_long"), do: :value_long
  defp key_atom("value_bool"), do: :value_bool
  defp key_atom("value_string"), do: :value_string
  defp key_atom("raw_value_text"), do: :raw_value_text
  defp key_atom("quality_state"), do: :quality_state
  defp key_atom("generation_time"), do: :generation_time
  defp key_atom("receipt_time"), do: :receipt_time
  defp key_atom("provenance_json"), do: :provenance_json
  defp key_atom("realm"), do: :realm
  defp key_atom("data_source_id"), do: :data_source_id
  defp key_atom("binding_id"), do: :binding_id
  defp key_atom("source_endpoint_id"), do: :source_endpoint_id
  defp key_atom("replay_run_id"), do: :replay_run_id
  defp key_atom("observation_id"), do: :observation_id
  defp key_atom("observation_identity_id"), do: :observation_identity_id
  defp key_atom("validity_state"), do: :validity_state
  defp key_atom("bucket_start"), do: :bucket_start
  defp key_atom("bucket_min"), do: :bucket_min
  defp key_atom("bucket_max"), do: :bucket_max
  defp key_atom("bucket_mean"), do: :bucket_mean
  defp key_atom("sample_count"), do: :sample_count
  defp key_atom("worst_quality_state"), do: :worst_quality_state
  defp key_atom("latest_receipt_time"), do: :latest_receipt_time
  defp key_atom("retention_starts_at"), do: :retention_starts_at
  defp key_atom(_key), do: nil
end
