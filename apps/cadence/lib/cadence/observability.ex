defmodule Cadence.Observability do
  @moduledoc """
  Operational observability setup for the Cadence domain application.

  Spacecraft telemetry belongs under `Cadence.Telemetry`; this module owns
  instrumentation that describes how the Cadence application itself behaves.
  """

  alias Cadence.Observability.LogExporter
  alias OpenTelemetry.{Ctx, Span}

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @repo_event_prefix [:cadence, :repo]

  @spec setup_repo_tracing() :: :ok
  def setup_repo_tracing do
    OpentelemetryEcto.setup(@repo_event_prefix, db_statement: :disabled)
  end

  @spec log_exporter_child_spec() :: Supervisor.child_spec() | nil
  def log_exporter_child_spec do
    config = Application.get_env(:cadence, :otel_logs, [])

    if Keyword.get(config, :enabled, false) and is_binary(config[:endpoint]) do
      Supervisor.child_spec({LogExporter, Keyword.delete(config, :enabled)}, id: LogExporter)
    end
  end

  @spec with_span(binary(), map(), (-> result)) :: result when result: var
  def with_span(name, start_opts, fun)
      when is_binary(name) and is_map(start_opts) and is_function(fun, 0) do
    Tracer.with_span name, start_opts do
      fun.()
    end
  end

  @spec with_span(Ctx.t(), binary(), map(), (-> result)) :: result when result: var
  def with_span(parent_context, name, start_opts, fun)
      when is_binary(name) and is_map(start_opts) and is_function(fun, 0) do
    Tracer.with_span parent_context, name, start_opts do
      fun.()
    end
  end

  @spec with_root_span(binary(), map(), (-> result)) :: result when result: var
  def with_root_span(name, start_opts, fun)
      when is_binary(name) and is_map(start_opts) and is_function(fun, 0) do
    with_span(Ctx.new(), name, start_opts, fun)
  end

  @spec current_context() :: Ctx.t()
  def current_context, do: Ctx.get_current()

  @spec current_span_context() :: OpenTelemetry.span_ctx() | :undefined
  def current_span_context, do: Tracer.current_span_ctx()

  @spec links([term()]) :: [OpenTelemetry.link()]
  def links(span_contexts) when is_list(span_contexts) do
    span_contexts
    |> Enum.filter(&Span.is_valid/1)
    |> OpenTelemetry.links()
  end

  @spec set_attributes(map()) :: boolean()
  def set_attributes(attributes) when is_map(attributes) do
    Tracer.set_attributes(attributes)
  end

  @spec add_event(binary(), map()) :: boolean()
  def add_event(name, attributes \\ %{}) when is_binary(name) and is_map(attributes) do
    Tracer.add_event(name, attributes)
  end

  @spec log(Logger.level(), binary(), binary(), keyword()) :: :ok
  def log(level, event_name, message, metadata \\ [])
      when is_atom(level) and is_binary(event_name) and is_binary(message) and is_list(metadata) do
    Logger.log(level, message, [cadence_event: event_name] ++ compact_metadata(metadata))
  end

  @spec mark_ok() :: boolean()
  def mark_ok do
    _ = Tracer.set_attribute("cadence.outcome", "ok")
    Tracer.set_status(:ok)
  end

  @spec mark_error(binary()) :: boolean()
  def mark_error(operation) when is_binary(operation) do
    _ = Tracer.set_attribute("cadence.outcome", "error")
    Tracer.set_status(:error, operation)
  end

  @spec error_class(term()) :: binary()
  def error_class(reason) when is_atom(reason), do: Atom.to_string(reason)
  def error_class({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  def error_class(%{__struct__: module}) when is_atom(module), do: inspect(module)
  def error_class(_reason), do: "unknown"

  defp compact_metadata(metadata) do
    Enum.reject(metadata, fn {_key, value} -> is_nil(value) or value == "" end)
  end
end
