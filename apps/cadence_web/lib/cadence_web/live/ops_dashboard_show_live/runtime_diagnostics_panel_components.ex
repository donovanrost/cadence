defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheSummaryComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeNoRefreshSummaryComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponents

  attr(:diagnostics, :map, required: true)
  attr(:dashboard_lifecycle_events, :list, default: [])
  attr(:dashboard_current_path, :string, default: nil)

  def diagnostics_panel(assigns) do
    assigns = assign(assigns, :presentation, presentation(assigns))

    ~H"""
    <.vue
      id={@presentation.root.attrs["id"]}
      v-component="RuntimeDiagnosticsPanel"
      presentation={@presentation}
      v-ssr={false}
      class={@presentation.root.attrs["class"]}
      data-runtime-invalidation-events={
        @presentation.root.attrs["data-runtime-invalidation-events"]
      }
      data-runtime-invalidation-artifacts={
        @presentation.root.attrs["data-runtime-invalidation-artifacts"]
      }
      data-runtime-invalidation-boundaries={
        @presentation.root.attrs["data-runtime-invalidation-boundaries"]
      }
      data-runtime-invalidation-context-matches={
        @presentation.root.attrs["data-runtime-invalidation-context-matches"]
      }
      data-runtime-invalidation-context-filtered={
        @presentation.root.attrs["data-runtime-invalidation-context-filtered"]
      }
      data-runtime-invalidation-context-filter-reasons={
        @presentation.root.attrs["data-runtime-invalidation-context-filter-reasons"]
      }
      data-runtime-invalidation-refresh-allowed={
        @presentation.root.attrs["data-runtime-invalidation-refresh-allowed"]
      }
      data-runtime-invalidation-refresh-suppressed={
        @presentation.root.attrs["data-runtime-invalidation-refresh-suppressed"]
      }
      data-runtime-invalidation-refresh-suppress-reasons={
        @presentation.root.attrs["data-runtime-invalidation-refresh-suppress-reasons"]
      }
      data-runtime-refresh-status={@presentation.root.attrs["data-runtime-refresh-status"]}
      data-runtime-refresh-reason={@presentation.root.attrs["data-runtime-refresh-reason"]}
      data-runtime-active-refresh-mode={
        @presentation.root.attrs["data-runtime-active-refresh-mode"]
      }
      data-runtime-active-refresh-started-at={
        @presentation.root.attrs["data-runtime-active-refresh-started-at"]
      }
      data-runtime-visible-refresh-action={
        @presentation.root.attrs["data-runtime-visible-refresh-action"]
      }
      data-runtime-last-refresh-started-at={
        @presentation.root.attrs["data-runtime-last-refresh-started-at"]
      }
      data-runtime-last-refresh-finished-at={
        @presentation.root.attrs["data-runtime-last-refresh-finished-at"]
      }
      data-runtime-last-refresh-duration-ms={
        @presentation.root.attrs["data-runtime-last-refresh-duration-ms"]
      }
      data-runtime-refresh-starts={@presentation.root.attrs["data-runtime-refresh-starts"]}
      data-runtime-refresh-cancellations={
        @presentation.root.attrs["data-runtime-refresh-cancellations"]
      }
      data-runtime-refresh-coalesced={
        @presentation.root.attrs["data-runtime-refresh-coalesced"]
      }
      data-runtime-refresh-noops={@presentation.root.attrs["data-runtime-refresh-noops"]}
      data-runtime-refresh-failures={
        @presentation.root.attrs["data-runtime-refresh-failures"]
      }
      data-runtime-refresh-ignored={@presentation.root.attrs["data-runtime-refresh-ignored"]}
      data-runtime-refresh-ignored-resolve-ids={
        @presentation.root.attrs["data-runtime-refresh-ignored-resolve-ids"]
      }
      data-runtime-canceled-resolves={
        @presentation.root.attrs["data-runtime-canceled-resolves"]
      }
      data-runtime-failed-resolves={
        @presentation.root.attrs["data-runtime-failed-resolves"]
      }
      data-runtime-source-execution-degraded-identities={
        @presentation.root.attrs["data-runtime-source-execution-degraded-identities"]
      }
      data-runtime-source-execution-degraded-actions={
        @presentation.root.attrs["data-runtime-source-execution-degraded-actions"]
      }
      data-runtime-source-capability-statuses={
        @presentation.root.attrs["data-runtime-source-capability-statuses"]
      }
      data-runtime-source-capability-postures={
        @presentation.root.attrs["data-runtime-source-capability-postures"]
      }
      data-runtime-source-dependency-evidence={
        @presentation.root.attrs["data-runtime-source-dependency-evidence"]
      }
      data-runtime-source-dependency-degraded-count={
        @presentation.root.attrs["data-runtime-source-dependency-degraded-count"]
      }
    />
    """
  end

  def presentation(assigns) do
    diagnostics = assigns.diagnostics

    %{
      root: %{
        attrs:
          runtime_attributes(diagnostics)
          |> Map.put("id", "dashboard-diagnostics-panel")
          |> Map.put("class", "space-y-5")
      },
      engine_section:
        child_presentation(
          "dashboard-diagnostics-engine-section-component",
          diagnostics_section_presentation("Engine", diagnostics.engine_rows)
        ),
      cache_summary: cache_summary_presentation(diagnostics.cache_summary),
      runtime_section:
        child_presentation(
          "dashboard-diagnostics-runtime-section-component",
          diagnostics_section_presentation("Runtime", diagnostics.runtime_rows)
        ),
      degraded_source_summary:
        degraded_source_summary_presentation(diagnostics.source_execution_degraded_summary),
      degraded_source_drilldowns:
        degraded_source_drilldowns_presentation(diagnostics.source_execution_degraded_drilldowns),
      source_capability_postures:
        source_capability_postures_presentation(
          Map.get(diagnostics, :source_capability_postures, [])
        ),
      source_dependency_causes:
        source_dependency_causes_presentation(
          Map.get(diagnostics, :source_dependency_evidence, [])
        ),
      no_refresh_summary: no_refresh_summary_presentation(diagnostics.no_refresh_summary),
      invalidation_section:
        child_presentation(
          "dashboard-diagnostics-invalidation-section-component",
          diagnostics_section_presentation("Invalidation", diagnostics.invalidation_rows)
        ),
      recent_invalidations:
        child_presentation(
          "dashboard-recent-invalidations-component",
          RuntimeRecentInvalidationsComponents.recent_invalidations_presentation(
            diagnostics.recent_invalidations,
            Map.get(assigns, :dashboard_lifecycle_events, []),
            Map.get(assigns, :dashboard_current_path)
          )
        )
    }
  end

  defp runtime_attributes(diagnostics) do
    raw_attributes(%{
      "data-runtime-invalidation-events" => diagnostics.invalidation_event_count,
      "data-runtime-invalidation-artifacts" => diagnostics.invalidation_artifact_count,
      "data-runtime-invalidation-boundaries" => diagnostics.invalidation_boundary_summary,
      "data-runtime-invalidation-context-matches" => diagnostics.invalidation_context_match_count,
      "data-runtime-invalidation-context-filtered" =>
        diagnostics.invalidation_context_filtered_count,
      "data-runtime-invalidation-context-filter-reasons" =>
        diagnostics.invalidation_context_filter_reasons,
      "data-runtime-invalidation-refresh-allowed" =>
        diagnostics.invalidation_refresh_allowed_count,
      "data-runtime-invalidation-refresh-suppressed" =>
        diagnostics.invalidation_refresh_suppressed_count,
      "data-runtime-invalidation-refresh-suppress-reasons" =>
        diagnostics.invalidation_refresh_suppress_reasons,
      "data-runtime-refresh-status" => diagnostics.refresh_status,
      "data-runtime-refresh-reason" => diagnostics.refresh_reason,
      "data-runtime-active-refresh-mode" => diagnostics.active_refresh_mode,
      "data-runtime-active-refresh-started-at" => diagnostics.active_refresh_started_at,
      "data-runtime-visible-refresh-action" => diagnostics.visible_refresh_action,
      "data-runtime-last-refresh-started-at" => diagnostics.last_refresh_started_at,
      "data-runtime-last-refresh-finished-at" => diagnostics.last_refresh_finished_at,
      "data-runtime-last-refresh-duration-ms" => diagnostics.last_refresh_duration_ms,
      "data-runtime-refresh-starts" => diagnostics.refresh_starts,
      "data-runtime-refresh-cancellations" => diagnostics.refresh_cancellations,
      "data-runtime-refresh-coalesced" => diagnostics.refresh_coalesced,
      "data-runtime-refresh-noops" => diagnostics.refresh_noops,
      "data-runtime-refresh-failures" => diagnostics.refresh_failures,
      "data-runtime-refresh-ignored" => diagnostics.refresh_ignored,
      "data-runtime-refresh-ignored-resolve-ids" => diagnostics.refresh_ignored_resolve_ids,
      "data-runtime-canceled-resolves" => diagnostics.canceled_resolve_count,
      "data-runtime-failed-resolves" => diagnostics.failed_resolve_count,
      "data-runtime-source-execution-degraded-identities" =>
        diagnostics.source_execution_degraded_identities,
      "data-runtime-source-execution-degraded-actions" =>
        diagnostics.source_execution_degraded_actions,
      "data-runtime-source-capability-statuses" =>
        Map.get(diagnostics, :source_capability_statuses_text),
      "data-runtime-source-capability-postures" =>
        Map.get(diagnostics, :source_capability_posture_text),
      "data-runtime-source-dependency-evidence" =>
        Map.get(diagnostics, :source_dependency_evidence_text),
      "data-runtime-source-dependency-degraded-count" =>
        Map.get(diagnostics, :source_dependency_degraded_count)
    })
  end

  defp diagnostics_section_presentation(title, rows) do
    %{
      root: %{
        tag: "section",
        class: "space-y-2",
        attrs: %{"data-diagnostics-section" => title}
      },
      title: %{tag: "h3", class: "hud-label", attrs: %{}, body: title},
      rows: %{
        tag: "dl",
        class: "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
        attrs: %{},
        items:
          rows
          |> Enum.with_index()
          |> Enum.map(fn {row, index} -> diagnostics_row_dto(row, index) end)
      }
    }
  end

  defp cache_summary_presentation(%{visible?: true} = summary) do
    child_presentation(
      "dashboard-cache-summary-component",
      RuntimeCacheSummaryComponents.cache_summary_presentation(summary)
    )
  end

  defp cache_summary_presentation(_summary), do: nil

  defp degraded_source_summary_presentation(%{visible?: true} = summary) do
    child_presentation(
      "dashboard-source-execution-degraded-summary-component",
      RuntimeDegradedSourceComponents.degraded_source_summary_presentation(summary)
    )
  end

  defp degraded_source_summary_presentation(_summary), do: nil

  defp degraded_source_drilldowns_presentation([_drilldown | _rest] = drilldowns) do
    child_presentation(
      "dashboard-degraded-source-drilldowns-component",
      RuntimeDegradedSourceComponents.degraded_source_drilldowns_presentation(drilldowns)
    )
  end

  defp degraded_source_drilldowns_presentation(_drilldowns), do: nil

  defp source_capability_postures_presentation([_posture | _rest] = postures) do
    child_presentation(
      "dashboard-source-capability-postures-component",
      RuntimeDegradedSourceComponents.source_capability_postures_presentation(postures)
    )
  end

  defp source_capability_postures_presentation(_postures), do: nil

  defp source_dependency_causes_presentation([_dependency | _rest] = dependencies) do
    child_presentation(
      "dashboard-source-dependency-causes-component",
      RuntimeDegradedSourceComponents.source_dependency_causes_presentation(dependencies)
    )
  end

  defp source_dependency_causes_presentation(_dependencies), do: nil

  defp no_refresh_summary_presentation(%{visible?: true} = summary) do
    child_presentation(
      "dashboard-no-refresh-summary-component",
      RuntimeNoRefreshSummaryComponents.no_refresh_summary_presentation(summary)
    )
  end

  defp no_refresh_summary_presentation(_summary), do: nil

  defp child_presentation(id, presentation) do
    %{
      root: %{attrs: %{"id" => id, "class" => "contents"}},
      presentation: presentation
    }
  end

  defp diagnostics_row_dto(row, index) do
    label = rendered_string(row.label)

    %{
      key: index,
      label: %{tag: "dt", class: "text-base-content/60", attrs: %{}, body: label},
      value: %{
        tag: "dd",
        class: "font-mono text-base-content break-all",
        attrs: %{"data-diagnostics-field" => label},
        body: rendered_string(row.value)
      }
    }
  end

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_string(value))
    end)
  end

  defp rendered_string(nil), do: ""
  defp rendered_string(value) when is_binary(value), do: value
  defp rendered_string(value), do: to_string(value)
end
