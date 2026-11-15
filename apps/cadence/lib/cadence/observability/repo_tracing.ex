defmodule Cadence.Observability.RepoTracing do
  @moduledoc """
  The Repo's query spans: OpentelemetryEcto 1.2.0's handler, with an O(1) parent-context lookup.

  OpentelemetryEcto looked the trace context up with
  `OpentelemetryProcessPropagator.fetch_ctx(self())`, i.e. `process_info(self(), :dictionary)`: a
  copy of the WHOLE process dictionary on every query (and, with no context, again for the
  caller's). A process holding a large memo paid O(dictionary) per query (step 4, 11-15: 77 % of
  a configuration apply's CPU; devops measured ~2 µs per KiB per query). No library option skips
  it (opentelemetry_ecto 1.2.0 and opentelemetry_process_propagator 0.3.0 are the latest).

  Here the context is read by key, never by copying a dictionary:

  - the calling process's own context: `OpenTelemetry.Ctx.get_current/0` semantics, read straight
    from its `$__current_otel_ctx` key;
  - otherwise the first `$callers` process's, via `process_info(pid, {:dictionary, key})`
    (OTP 26+), which returns only that key.

  Spans are otherwise the library's: the same name, kind, attributes and error status, with
  `db_statement: :disabled` as configured. The repo's config is read once per query, not three
  times.
  """

  require OpenTelemetry.Tracer

  @ctx_key :"$__current_otel_ctx"

  @doc "Attaches the handler to `event_prefix ++ [:query]` (OpentelemetryEcto.setup/2's options)."
  @spec setup([atom()], keyword()) :: :ok | {:error, :already_exists}
  def setup(event_prefix, config \\ []) do
    event = event_prefix ++ [:query]
    :telemetry.attach({__MODULE__, event}, event, &__MODULE__.handle_event/4, config)
  end

  @doc false
  def handle_event(event, measurements, %{result: query_result} = metadata, config) do
    end_time = :opentelemetry.timestamp()
    start_time = end_time - measurements.total_time

    parent_token =
      case parent_context() do
        :undefined -> :undefined
        context -> OpenTelemetry.Ctx.attach(context)
      end

    span =
      OpenTelemetry.Tracer.start_span(span_name(event, metadata.source, config), %{
        start_time: start_time,
        attributes: attributes(measurements, metadata, config),
        kind: :client
      })

    with {:error, error} <- query_result,
         do:
           OpenTelemetry.Span.set_status(span, OpenTelemetry.status(:error, format_error(error)))

    OpenTelemetry.Span.end_span(span)

    if parent_token != :undefined, do: OpenTelemetry.Ctx.detach(parent_token)
  end

  defp span_name(event, source, config) do
    prefix =
      case Keyword.fetch(config, :span_prefix) do
        {:ok, prefix} -> prefix
        :error -> Enum.join(event, ".")
      end

    if source != nil, do: prefix <> ":#{source}", else: prefix
  end

  # The library's attributes; the repo's config read once per query.
  defp attributes(measurements, %{query: query, source: source, repo: repo, type: type}, config) do
    repo_config = repo.config()
    database = repo_config[:database]
    time_unit = Keyword.get(config, :time_unit, :microsecond)

    %{
      "db.type": db_type(type),
      source: source,
      "db.instance": database,
      "db.name": database,
      "db.url": db_url(repo_config)
    }
    |> Map.put(
      total_time_key(time_unit),
      System.convert_time_unit(measurements.total_time, :native, time_unit)
    )
    |> add_measurements(measurements, time_unit)
    |> maybe_add_db_statement(Keyword.get(config, :db_statement, :disabled), query)
    |> maybe_add_db_system(repo.__adapter__())
    |> Map.merge(Keyword.get(config, :additional_attributes, %{}))
  end

  defp db_url(repo_config) do
    case repo_config[:url] do
      nil -> URI.to_string(%URI{scheme: "ecto", host: repo_config[:hostname]})
      url -> url
    end
  end

  @doc """
  The context a query span parents to: this process's, else its first caller's (a Task's
  parent), else `:undefined`. Reads one key each; never copies a process dictionary.
  """
  @spec parent_context() :: term()
  def parent_context do
    case Process.get(@ctx_key, :undefined) do
      :undefined -> caller_context(Process.get(:"$callers", []))
      context -> context
    end
  end

  defp caller_context([caller | _rest]) when is_pid(caller) do
    case Process.info(caller, {:dictionary, @ctx_key}) do
      {{:dictionary, @ctx_key}, :undefined} -> :undefined
      {{:dictionary, @ctx_key}, context} -> context
      _dead -> :undefined
    end
  end

  defp caller_context(_callers), do: :undefined

  defp db_type(:ecto_sql_query), do: :sql
  defp db_type(type), do: type

  defp format_error(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_error(_error), do: ""

  @measurements [:decode_time, :query_time, :queue_time, :idle_time]
  @time_units [:second, :millisecond, :microsecond, :nanosecond, :native]
  @total_time_keys Map.new(@time_units, &{&1, :"total_time_#{&1}s"})

  defp total_time_key(time_unit), do: Map.fetch!(@total_time_keys, time_unit)

  defp add_measurements(attributes, measurements, time_unit) do
    Enum.reduce(measurements, attributes, fn
      {key, value}, acc when not is_nil(value) and key in @measurements ->
        Map.put(
          acc,
          measurement_key(key, time_unit),
          System.convert_time_unit(value, :native, time_unit)
        )

      _other, acc ->
        acc
    end)
  end

  # The library's attribute names (`query_time_microseconds`, ...), built at compile time from
  # the fixed measurement keys and time units.
  @measurement_keys for key <- @measurements,
                        unit <- @time_units,
                        into: %{},
                        do: {{key, unit}, :"#{key}_#{unit}s"}

  defp measurement_key(key, time_unit), do: Map.fetch!(@measurement_keys, {key, time_unit})

  defp maybe_add_db_statement(attributes, :enabled, query),
    do: Map.put(attributes, :"db.statement", query)

  defp maybe_add_db_statement(attributes, sanitizer, query) when is_function(sanitizer, 1),
    do: Map.put(attributes, :"db.statement", sanitizer.(query))

  defp maybe_add_db_statement(attributes, _disabled, _query), do: attributes

  defp maybe_add_db_system(attributes, Ecto.Adapters.Postgres),
    do: Map.put(attributes, :"db.system", :postgresql)

  defp maybe_add_db_system(attributes, _adapter), do: attributes
end
