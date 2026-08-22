defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs

  attr :summary, :map, required: true

  def degraded_source_summary(%{summary: %{visible?: true}} = assigns) do
    ~H"""
    <section
      id="dashboard-source-execution-degraded-summary"
      class="border border-warning/30 bg-warning/10 px-3 py-2 text-sm"
      data-diagnostics-section="Source execution degraded"
      data-source-execution-degraded-count={@summary.count}
      data-source-execution-degraded-identity={@summary.identity}
      data-source-execution-degraded-status={@summary.status}
      data-source-execution-runtime-action={@summary.runtime_action}
      data-source-execution-operator-action={@summary.operator_action}
      data-source-execution-realm={@summary.realm}
      data-source-execution-data-source={@summary.data_source_id}
      data-source-execution-binding={@summary.source_binding_id}
      data-source-execution-request={@summary.request_id}
    >
      <h3 class="hud-label">Source execution degraded</h3>
      <p class="mt-1 text-base-content">{@summary.headline}</p>
      <dl class="mt-2 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <dt class="text-base-content/60">Source</dt>
        <dd class="font-mono text-base-content break-all" data-source-execution-field="Source">
          {@summary.identity}
        </dd>
        <dt class="text-base-content/60">Status</dt>
        <dd class="font-mono text-base-content break-all" data-source-execution-field="Status">
          {@summary.status}
        </dd>
        <dt class="text-base-content/60">Runtime</dt>
        <dd class="font-mono text-base-content break-all" data-source-execution-field="Runtime">
          {@summary.runtime_action}
        </dd>
        <dt class="text-base-content/60">Operator</dt>
        <dd class="font-mono text-base-content break-all" data-source-execution-field="Operator">
          {@summary.operator_action}
        </dd>
      </dl>
    </section>
    """
  end

  def degraded_source_summary(assigns), do: ~H""

  attr :drilldowns, :list, required: true

  def degraded_source_drilldowns(%{drilldowns: []} = assigns), do: ~H""

  def degraded_source_drilldowns(assigns) do
    ~H"""
    <section class="space-y-2" data-diagnostics-section="Degraded sources">
     <h3 class="hud-label">Degraded sources</h3>
     <div id="dashboard-degraded-source-drilldowns" class="space-y-2">
       <button
         :for={drilldown <- @drilldowns}
         type="button"
         phx-click="open_evidence"
         {EvidenceAttrs.degraded_source(drilldown)}
         class="w-full border border-warning/30 bg-warning/5 px-2 py-2 text-left text-xs hover:bg-warning/10"
         data-degraded-source-drilldown={drilldown.request_id}
         data-degraded-source-logical-source={drilldown.logical_source}
         data-degraded-source-status={drilldown.status}
         data-degraded-source-runtime-action={drilldown.runtime_action}
         data-degraded-source-operator-action={drilldown.operator_action}
       >
         <span class="flex items-center gap-2">
           <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5 text-warning" />
           <span class="font-mono text-base-content break-all">
             {degraded_source_label(drilldown)}
           </span>
         </span>
         <span class="mt-1 block font-mono text-base-content/60 break-all">
           {degraded_source_actions(drilldown)}
         </span>
       </button>
     </div>
    </section>
    """
  end

  attr :postures, :list, default: []

  def source_capability_postures(%{postures: postures} = assigns) when not is_list(postures) do
    assigns
    |> assign(:postures, [])
    |> source_capability_postures()
  end

  def source_capability_postures(%{postures: []} = assigns), do: ~H""

  def source_capability_postures(assigns) do
    ~H"""
    <section
      id="dashboard-source-capability-postures"
      class="space-y-2"
      data-diagnostics-section="Source capability posture"
      data-source-capability-posture-count={length(@postures)}
    >
      <h3 class="hud-label">Source capability posture</h3>
      <div class="space-y-2">
        <button
          :for={posture <- @postures}
          type="button"
          phx-click="open_evidence"
          {EvidenceAttrs.source_capability_posture(posture)}
          class="w-full border border-base-content/15 bg-base-200/40 px-2 py-2 text-left text-xs hover:bg-base-200/70"
          data-source-capability-posture={posture.request_id}
          data-source-capability-logical-source={posture.logical_source}
          data-source-capability-status={posture.status}
          data-source-capability-requested-axis={posture.requested_time_axis}
          data-source-capability-executed-axis={posture.executed_time_axis}
          data-source-capability-supported-axes={posture.supported_time_axes}
          data-source-capability-requested-products={Map.get(posture, :requested_products)}
          data-source-capability-supported-products={Map.get(posture, :supported_products)}
        >
          <span class="flex items-center gap-2">
            <.icon
              name={source_capability_icon(posture)}
              class={"h-3.5 w-3.5 #{source_capability_icon_class(posture)}"}
            />
            <span class="font-medium text-base-content">
              {source_capability_headline(posture)}
            </span>
          </span>
          <span
            class="mt-1 block font-mono text-base-content break-all"
            data-source-capability-field="Clock"
          >
            {source_capability_clock(posture)}
          </span>
          <span
            class="mt-1 block font-mono text-base-content/60 break-all"
            data-source-capability-field="Support"
          >
            {source_capability_support(posture)}
          </span>
        </button>
      </div>
    </section>
    """
  end

  attr :dependencies, :list, default: []

  def source_dependency_causes(%{dependencies: dependencies} = assigns)
      when not is_list(dependencies) do
    assigns
    |> assign(:dependencies, [])
    |> source_dependency_causes()
  end

  def source_dependency_causes(%{dependencies: []} = assigns), do: ~H""

  def source_dependency_causes(assigns) do
    ~H"""
    <section
      id="dashboard-source-dependency-causes"
      class="space-y-2"
      data-diagnostics-section="Source dependency causes"
      data-source-dependency-cause-count={length(@dependencies)}
    >
      <h3 class="hud-label">Source dependency causes</h3>
      <div class="space-y-2">
        <button
          :for={dependency <- @dependencies}
          type="button"
          phx-click="open_evidence"
          {EvidenceAttrs.degraded_source(upstream_source_evidence(dependency))}
          class="w-full border border-warning/30 bg-warning/5 px-2 py-2 text-left text-xs hover:bg-warning/10"
          data-source-dependency-cause={dependency.request_id}
          data-source-dependency-request-source={dependency.request_logical_source}
          data-source-dependency-upstream-source={dependency.logical_source}
          data-source-dependency-upstream-request={dependency.upstream_request_id}
          data-source-dependency-upstream-status={dependency.upstream_status}
          data-source-dependency-upstream-runtime-action={dependency.upstream_runtime_action}
          data-source-dependency-upstream-watermark-state={
            dependency.upstream_watermark_freshness_state
          }
        >
          <span class="flex items-center gap-2">
            <.icon name="hero-arrow-path" class="h-3.5 w-3.5 text-warning" />
            <span class="font-medium text-base-content">
              {dependency_cause_headline(dependency)}
            </span>
          </span>
          <span
            class="mt-1 block font-mono text-base-content break-all"
            data-source-dependency-field="Path"
          >
            {dependency_path(dependency)}
          </span>
          <span
            class="mt-1 block font-mono text-base-content/60 break-all"
            data-source-dependency-field="Upstream"
          >
            {dependency_upstream_state(dependency)}
          </span>
        </button>
      </div>
    </section>
    """
  end

  defp degraded_source_label(drilldown) do
    [
      Map.get(drilldown, :logical_source),
      Map.get(drilldown, :request_id),
      Map.get(drilldown, :status)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp degraded_source_actions(drilldown) do
    [
      Map.get(drilldown, :runtime_action),
      Map.get(drilldown, :operator_action)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp source_capability_icon(%{status: "unsupported"}), do: "hero-exclamation-triangle"
  defp source_capability_icon(%{status: "fallback"}), do: "hero-arrow-path"
  defp source_capability_icon(_posture), do: "hero-check-circle"

  defp source_capability_icon_class(%{status: "unsupported"}), do: "text-error"
  defp source_capability_icon_class(%{status: "fallback"}), do: "text-warning"
  defp source_capability_icon_class(_posture), do: "text-success"

  defp source_capability_headline(posture) do
    [
      Map.get(posture, :logical_source),
      Map.get(posture, :request_id),
      Map.get(posture, :status)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp source_capability_clock(posture) do
    [
      Map.get(posture, :requested_time_axis),
      "->",
      Map.get(posture, :executed_time_axis)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp source_capability_support(posture) do
    [
      supported_values("sampling", Map.get(posture, :supported_sampling)),
      supported_values("products", Map.get(posture, :supported_products)),
      supported_values("axes", Map.get(posture, :supported_time_axes)),
      details_value("fallback", Map.get(posture, :fallbacks)),
      details_value("unsupported", Map.get(posture, :unsupported))
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp supported_values(_label, value) when value in [nil, ""], do: nil
  defp supported_values(label, value), do: "#{label}=#{value}"

  defp details_value(_label, value) when value in [nil, ""], do: nil
  defp details_value(label, value), do: "#{label}=#{value}"

  defp upstream_source_evidence(dependency) do
    %{
      request_id: Map.get(dependency, :upstream_request_id),
      logical_source: Map.get(dependency, :logical_source),
      realm: Map.get(dependency, :upstream_realm),
      data_source_id: Map.get(dependency, :upstream_data_source_id),
      source_binding_id: Map.get(dependency, :upstream_source_binding_id)
    }
  end

  defp dependency_cause_headline(%{
         request_logical_source: "limits",
         logical_source: "telemetry"
       }),
       do: "Limits waiting on telemetry input"

  defp dependency_cause_headline(dependency) do
    [
      Map.get(dependency, :request_logical_source),
      "waiting on",
      Map.get(dependency, :logical_source),
      "input"
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp dependency_path(dependency) do
    [
      dependency_identity(
        Map.get(dependency, :request_logical_source),
        Map.get(dependency, :request_id)
      ),
      "->",
      dependency_identity(
        Map.get(dependency, :logical_source),
        Map.get(dependency, :upstream_request_id)
      )
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp dependency_identity(nil, request_id), do: request_id
  defp dependency_identity(source, nil), do: source
  defp dependency_identity(source, request_id), do: "#{source}:#{request_id}"

  defp dependency_upstream_state(dependency) do
    [
      Map.get(dependency, :upstream_status),
      Map.get(dependency, :upstream_runtime_action),
      Map.get(dependency, :upstream_watermark_freshness_state)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
