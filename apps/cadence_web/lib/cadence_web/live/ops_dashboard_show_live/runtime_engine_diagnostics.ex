defmodule CadenceWeb.OpsDashboardShowLive.RuntimeEngineDiagnostics do
  @moduledoc false

  alias Cadence.Dashboards.DataContext
  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatter
  alias CadenceWeb.OpsDashboardShowLive.RuntimeResult
  alias CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary

  def rows(engine_result) do
    [
      RuntimeDiagnosticFormatter.row("Resolve", resolve_mode(engine_result)),
      RuntimeDiagnosticFormatter.row(
        "Source requests",
        metadata(engine_result, :source_request_count)
      ),
      RuntimeDiagnosticFormatter.row(
        "Executed requests",
        metadata(engine_result, :executed_source_request_count)
      ),
      RuntimeDiagnosticFormatter.row(
        "Skipped requests",
        metadata(engine_result, :skipped_source_request_count)
      ),
      RuntimeDiagnosticFormatter.row("Plan cache", cache_status(engine_result, :plan_cache)),
      RuntimeDiagnosticFormatter.row("Source cache", source_cache_statuses(engine_result)),
      RuntimeDiagnosticFormatter.row("Frame cache", frame_cache_statuses(engine_result)),
      RuntimeDiagnosticFormatter.row(
        "Source dependencies",
        source_dependency_summary(engine_result)
      ),
      RuntimeDiagnosticFormatter.row(
        "Source dependency evidence",
        source_dependency_evidence_summary(engine_result)
      ),
      RuntimeDiagnosticFormatter.row("Time", context(engine_result, :time, :mode)),
      RuntimeDiagnosticFormatter.row("Realm", context(engine_result, :data, :realm)),
      RuntimeDiagnosticFormatter.row("Limits", context(engine_result, :limit, :semantics_mode)),
      RuntimeDiagnosticFormatter.row("Snapshot", boolean_metadata(engine_result, :snapshot?)),
      RuntimeDiagnosticFormatter.row(
        "Live append",
        boolean_metadata(engine_result, :live_append_eligible?)
      )
    ]
  end

  def resolve_mode(nil), do: nil
  def resolve_mode(result), do: RuntimeResult.resolve_mode_text(result)

  def metadata(nil, _key), do: nil
  def metadata(result, key), do: RuntimeResult.metadata(result, key)

  def cache_status(nil, _key), do: nil
  def cache_status(result, :plan_cache), do: RuntimeCacheDiagnostics.plan_status(result)
  def cache_status(_result, _key), do: nil

  def source_cache_statuses(result), do: RuntimeCacheDiagnostics.source_statuses(result)

  def frame_cache_statuses(result), do: RuntimeCacheDiagnostics.frame_statuses(result)

  def source_dependency_count(result), do: length(source_dependencies(result))

  def source_dependency_summary(result) do
    result
    |> source_dependencies()
    |> Enum.map(&dependency_summary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
    |> case do
      [] -> nil
      summaries -> Enum.join(summaries, " ")
    end
  end

  def source_dependency_evidence_summary(result) do
    result
    |> SourceExecutionRuntimeSummary.build()
    |> Map.get(:source_dependencies, [])
    |> RuntimeSourceExecutionDiagnostics.dependency_evidence_summary()
  end

  def source_dependency_degraded_count(result) do
    result
    |> SourceExecutionRuntimeSummary.build()
    |> Map.get(:source_dependencies, [])
    |> RuntimeSourceExecutionDiagnostics.dependency_degraded_count()
  end

  def boolean_metadata(nil, _key), do: nil

  def boolean_metadata(result, key) do
    if RuntimeResult.boolean_metadata?(result, key), do: "true", else: "false"
  end

  def context(nil, _context, _key), do: nil
  def context(result, :time, key), do: RuntimeResult.metadata_path(result, [:time, key])

  def context(result, context, key) do
    result
    |> RuntimeResult.first_planned_source_request()
    |> case do
      nil ->
        nil

      request ->
        request_context_value(request, context, key)
    end
  end

  defp request_context_value(request, :data, key)
       when key in [:data_source_id, :source_binding_id, :dataset, :source_mode, :view] do
    DataContext.source_value(request.data_context, request.logical_source, key)
  end

  defp request_context_value(request, context, key) do
    request
    |> Map.fetch!(context_field(context))
    |> Map.get(key)
  end

  defp context_field(:data), do: :data_context
  defp context_field(:limit), do: :limit_context

  defp source_dependencies(result) do
    result
    |> RuntimeResult.planned_source_requests()
    |> Enum.flat_map(fn request ->
      request
      |> request_source_dependencies()
      |> Enum.map(&Map.put(&1, :request_logical_source, request_logical_source(request)))
    end)
  end

  defp request_source_dependencies(request) when is_map(request) do
    request
    |> Map.get(:source_dependencies, Map.get(request, "source_dependencies", []))
    |> case do
      dependencies when is_list(dependencies) -> dependencies
      _dependencies -> []
    end
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalize_dependency/1)
  end

  defp request_source_dependencies(_request), do: []

  defp normalize_dependency(dependency) do
    %{
      logical_source: dependency_value(dependency, :logical_source),
      reason: dependency_value(dependency, :reason),
      products: dependency_products(dependency_value(dependency, :products))
    }
  end

  defp dependency_summary(%{
         request_logical_source: request_source,
         logical_source: dependency_source,
         products: products,
         reason: reason
       }) do
    product_text =
      products
      |> Enum.map(&value_text/1)
      |> Enum.reject(&(&1 == ""))
      |> case do
        [] -> value_text(reason)
        product_values -> Enum.join(product_values, "+")
      end

    [
      value_text(request_source),
      "->",
      value_text(dependency_source),
      ":",
      product_text
    ]
    |> Enum.join()
  end

  defp dependency_value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key)))

  defp dependency_value(_map, _key), do: nil

  defp dependency_products(products) when is_list(products), do: products
  defp dependency_products(product) when not is_nil(product), do: [product]
  defp dependency_products(_products), do: []

  defp request_logical_source(request) when is_map(request),
    do: Map.get(request, :logical_source, Map.get(request, "logical_source"))

  defp request_logical_source(_request), do: nil

  defp value_text(nil), do: ""
  defp value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp value_text(value) when is_binary(value), do: value
  defp value_text(value), do: inspect(value)
end
