defmodule Cadence.Reads.Dashboards.ExplorationSample do
  @moduledoc "Server-only selected-sample read using bindings retained by the authorized Explore query."

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    PlannedSourceRequest,
    ResolutionContext,
    SourceRegistry,
    SourceRequestPlanning
  }

  def load(%{sample_id: nil}, _request, _result, _context), do: :not_selected

  def load(query, request, %DashboardResolveResult{} = result, %ResolutionContext{} = context) do
    with true <- result.dashboard_id == request.dashboard_id,
         [%PlannedSourceRequest{} = planned] <- result.planned_source_requests,
         true <-
           planned.organization_id == request.organization_id and
             planned.mission_id == request.mission_id,
         true <- planned.logical_source == :telemetry and planned.observables == [query.point_id],
         {:ok, receipt_time} <- selected_time(query.query["selected_time"]) do
      bindings =
        result.resolved_bindings_by_request_id
        |> Map.get(planned.request_id, [])
        |> selected_bindings(query.query)

      opts =
        SourceRequestPlanning.source_registry_opts(
          planned,
          ResolutionContext.to_engine_opts(context)
        )

      SourceRegistry.inspect_samples(
        planned,
        bindings,
        %{point_id: query.point_id, sample_id: query.sample_id, receipt_time: receipt_time},
        opts
      )
    else
      _ -> {:error, :missing_physical_sample_binding}
    end
  rescue
    _ -> {:error, :physical_sample_unavailable}
  catch
    _, _ -> {:error, :physical_sample_unavailable}
  end

  defp selected_bindings(bindings, %{
         "selected_data_source_id" => source,
         "selected_source_binding_id" => binding
       }) do
    Enum.filter(bindings, fn resolved ->
      resolved.data_source.data_source_id == source and resolved.binding.binding_id == binding
    end)
  end

  defp selected_bindings(bindings, _query), do: bindings

  defp selected_time(nil), do: {:ok, nil}

  defp selected_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} -> {:ok, time}
      _ -> :error
    end
  end
end
