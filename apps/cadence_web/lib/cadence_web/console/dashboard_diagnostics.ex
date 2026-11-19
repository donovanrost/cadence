defmodule CadenceWeb.Console.DashboardDiagnostics do
  @moduledoc """
  D18 diagnostics grouped by widget (fe-setup, docs/apogee/plans/dashboards-settings.md; ux U20:
  "so you can see which widget is slow or failing"), built from
  `Reads.Dashboards.ExecutionDiagnostics`' evidence collections and the published document's
  outline. Pure.

  A widget's sources are the planned source requests that feed it, each with its execution
  outcome and cache verdict; its warnings are the plan warnings naming it. Durations, per-request
  outcomes and errors aren't recorded yet, so `duration_ms`, `outcome` and `error` are null.
  """

  # SourceExecutionSemantics' outcome statuses, folded to the tab's closed four.
  @failed ~w(source_execution_failed facts_error source_unavailable)
  @degraded ~w(source_degraded unsupported_capability cache_stale)
  @not_run ~w(skipped)

  @doc "`model` is ExecutionDiagnostics.load/4's map; `outline` is Editor.outline/1's."
  @spec build(map(), map()) :: map()
  def build(%{collections: collections} = model, %{placements: placements}) do
    rows =
      Map.new(
        collections,
        &{&1.id, Enum.map(&1.rows, fn row -> Map.put(row, :details, details(row)) end)}
      )

    outcomes = Map.new(Map.get(rows, "source_execution", []), &{&1.identity, &1})
    cache = cache_by_request(Map.get(rows, "cache", []))
    warnings = Enum.filter(Map.get(rows, "plan", []), &Map.has_key?(&1.details, "warning_code"))

    requests_by_placement =
      for request <- Map.get(rows, "requests", []),
          placement <- split(request.details["placements"]),
          reduce: %{} do
        acc -> Map.update(acc, placement, [request], &[request | &1])
      end

    widgets =
      placements
      |> Enum.map(fn placement ->
        sources =
          requests_by_placement
          |> Map.get(placement.id, [])
          |> Enum.reverse()
          |> Enum.map(&source(&1, Map.get(outcomes, &1.identity), Map.get(cache, &1.identity)))

        widget_warnings =
          for warning <- warnings, warning.details["placement_id"] == placement.id do
            %{
              code: warning.details["warning_code"],
              severity: warning.status,
              field_name: warning.details["field_name"],
              message: nil
            }
          end

        %{
          placement_id: placement.id,
          title: placement.title,
          status: widget_status(sources, widget_warnings),
          sources: sources,
          warnings: widget_warnings
        }
      end)
      |> Enum.sort_by(&{rank(&1.status), &1.title || ""})

    %{
      version: model.document_version,
      loaded_at: model.loaded_at,
      widgets: widgets
    }
  end

  defp source(request, outcome, cache_status) do
    details = (outcome && outcome.details) || %{}

    code = outcome && outcome.status

    %{
      logical_source: request.details["logical_source"],
      status: source_status(code),
      status_code: code,
      cache: cache_word(details["cache_status"] || cache_status),
      cache_status: details["cache_status"] || cache_status,
      severity: details["severity"],
      retryable: details["retryable"],
      operator_action: details["operator_action"],
      warning_codes: split(details["warning_codes"]),
      duration_ms: nil,
      outcome: nil,
      error: nil
    }
  end

  # ok | degraded | failed | not_run (no outcome yet, or skipped).
  defp source_status(nil), do: "not_run"
  defp source_status(code) when code in @failed, do: "failed"
  defp source_status(code) when code in @degraded, do: "degraded"
  defp source_status(code) when code in @not_run, do: "not_run"
  defp source_status(_executed_or_cache_hit_miss), do: "ok"

  # ok | degraded | failed | not_run, the worst of its sources and warnings.
  defp widget_status([], []), do: "not_run"

  defp widget_status(sources, warnings) do
    cond do
      Enum.any?(sources, &(&1.status == "failed")) -> "failed"
      Enum.any?(sources, &(&1.status == "degraded")) -> "degraded"
      Enum.any?(warnings, &(&1.severity in ~w(error warning))) -> "degraded"
      Enum.all?(sources, &(&1.status == "not_run")) -> "not_run"
      true -> "ok"
    end
  end

  # Worst first.
  defp rank("failed"), do: 0
  defp rank("degraded"), do: 1
  defp rank("not_run"), do: 2
  defp rank(_ok), do: 3

  # The two-word verdict the Diagnostics tab shows ("From cache" / "Fresh"); unknown is null.
  defp cache_word(status) when status in ~w(hit stale), do: "cached"
  defp cache_word(status) when status in ~w(miss disabled), do: "fresh"
  defp cache_word(_unknown), do: nil

  defp cache_by_request(rows) do
    for row <- rows,
        row.details["layer"] == "source_result",
        is_binary(row.details["request_id"]),
        into: %{} do
      {row.details["request_id"], row.status}
    end
  end

  defp details(%{details: details}) when is_list(details),
    do: Map.new(details, &{&1.key, &1.value})

  defp details(_row), do: %{}

  # Evidence joins short lists with " · " (at most 12).
  defp split(nil), do: []
  defp split(""), do: []
  defp split(joined) when is_binary(joined), do: String.split(joined, " · ")
  defp split(_other), do: []
end
