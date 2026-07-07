defmodule CadenceWeb.OpsDashboardShowLive.SourceHealthComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs

  attr :health, :list, required: true

  def source_health_strip(assigns) do
    ~H"""
    <div
      :if={@health != []}
      id="dashboard-source-health"
      data-source-health={source_health_codes(@health)}
      data-source-cache={source_cache_codes(@health)}
      data-source-circuit={source_circuit_codes(@health)}
      data-source-execution={source_execution_codes(@health)}
      data-source-execution-severity={source_execution_severity_codes(@health)}
      data-source-execution-action={source_execution_action_codes(@health)}
      class="shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-base-300/60 bg-base-200/40 text-xs"
    >
      <span class="hud-label">Source status</span>
      <.source_health_badge :for={source <- @health} source={source} />
    </div>
    """
  end

  attr :source, :map, required: true

  defp source_health_badge(assigns) do
    ~H"""
    <details
      class="dropdown dropdown-end"
      data-source-health-detail={"#{@source.logical_source_text}:#{@source.state_text}"}
      data-source-cache-detail={"#{@source.logical_source_text}:#{@source.source_cache_text}"}
      data-source-circuit-detail={"#{@source.logical_source_text}:#{@source.circuit_state_text}"}
      data-source-execution-detail={"#{@source.logical_source_text}:#{@source.execution_status_text}"}
      data-source-execution-action-detail={"#{@source.logical_source_text}:#{@source.execution_operator_action_text}"}
    >
      <summary
        class={["badge badge-xs cursor-pointer", source_health_badge_class(@source)]}
        data-source-health-source={@source.logical_source_text}
        data-source-health-state={@source.state_text}
        data-source-cache-state={@source.source_cache_text}
        data-source-frame-cache-state={@source.frame_cache_text}
        data-source-circuit-state={@source.circuit_state_text}
        data-source-execution-status={@source.execution_status_text}
        data-source-execution-severity={@source.execution_severity_text}
        data-source-execution-action={@source.execution_operator_action_text}
        data-source-execution-runtime-action={@source.execution_runtime_action_text}
        data-source-execution-degraded={if @source.execution_degraded?, do: "true", else: "false"}
        data-source-execution-actionable={
          if @source.execution_actionable?, do: "true", else: "false"
        }
        data-source-execution-retryable={if @source.execution_retryable?, do: "true", else: "false"}
        title={@source.label}
      >
        {@source.label}
      </summary>
      <div class="dropdown-content z-[var(--z-popover)] mt-1 w-80 rounded border border-base-300 bg-base-100 p-2 text-xs shadow-lg">
        <div class="font-semibold text-base-content">{@source.label}</div>
        <p class="mt-1 text-base-content/70">
          Realm {@source.realm_text}; confidence {@source.confidence_text};
          source cache {status_or_none(@source.source_cache_text)};
          frame cache {status_or_none(@source.frame_cache_text)};
          execution {status_or_none(@source.execution_status_text)};
          action {status_or_none(@source.execution_operator_action_text)}.
        </p>
        <p :if={@source.circuit_state} class="mt-1 text-error">
          Circuit {@source.circuit_state_text}: {@source.source_warning_text}
        </p>
        <button
          type="button"
          phx-click="open_evidence"
          {EvidenceAttrs.source_health(@source)}
          class="mt-2 btn btn-xs btn-outline w-full justify-start"
          data-source-evidence-open
        >
          <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5" />
          Inspect evidence
        </button>
        <dl class="mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1">
          <%= for row <- @source.detail_rows do %>
            <dt class="text-base-content/60">{row.label}</dt>
            <dd class="font-mono text-base-content break-all" data-source-health-field={row.label}>
              {row.value}
            </dd>
          <% end %>
        </dl>
      </div>
    </details>
    """
  end

  defp source_health_codes(health) do
    Enum.map_join(health, ",", &"#{&1.logical_source_text}:#{&1.state_text}")
  end

  defp source_cache_codes(health) do
    health
    |> Enum.map_join(",", fn source ->
      "#{source.logical_source_text}:source=#{status_code(source.source_cache_text)};frame=#{status_code(source.frame_cache_text)}"
    end)
  end

  defp source_circuit_codes(health) do
    health
    |> Enum.map_join(",", fn source ->
      "#{source.logical_source_text}:#{status_code(source.circuit_state_text)}"
    end)
  end

  defp source_execution_codes(health) do
    health
    |> Enum.map_join(",", fn source ->
      "#{source.logical_source_text}:#{status_code(source.execution_status_text)}"
    end)
  end

  defp source_execution_severity_codes(health) do
    health
    |> Enum.map_join(",", fn source ->
      "#{source.logical_source_text}:#{status_code(source.execution_severity_text)}"
    end)
  end

  defp source_execution_action_codes(health) do
    health
    |> Enum.map_join(",", fn source ->
      "#{source.logical_source_text}:#{status_code(source.execution_operator_action_text)}"
    end)
  end

  defp status_code(nil), do: "none"
  defp status_code(""), do: "none"
  defp status_code(value), do: value |> to_string() |> String.replace(" ", "_")

  defp status_or_none(nil), do: "none"
  defp status_or_none(""), do: "none"
  defp status_or_none(value), do: value

  defp source_health_badge_class(%{state: :fresh}), do: "badge-success"
  defp source_health_badge_class(%{state: :stale}), do: "badge-warning"
  defp source_health_badge_class(%{state: :retention_gap}), do: "badge-error"
  defp source_health_badge_class(%{state: :unknown}), do: "badge-warning"
  defp source_health_badge_class(_source), do: "badge-info"
end
