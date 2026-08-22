defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusComponents do
  @moduledoc false

  use CadenceWeb, :html

  alias CadenceWeb.OpsDataSourcesLive.{
    SourceFocus,
    SourceFocusPresentation,
    SourceFocusResources
  }

  attr :focus, :map, required: true
  attr :resources, :map, required: true
  attr :mission_id, :string, required: true

  def resource_panel(assigns) do
    assigns =
      assign(
        assigns,
        :resource,
        SourceFocusResources.build(assigns.focus, assigns.resources, fn key, value ->
          resource_href(assigns.resources, assigns.mission_id, key, value)
        end)
      )

    ~H"""
    <div
      :if={@resource}
      id="source-focus-resource"
      class="mt-3 border-l-2 border-primary/70 pl-3"
      data-source-resource-selected-target={@resource.selected_target || ""}
      data-source-resource-selected-id={@resource.selected_id || ""}
      data-source-resource-transport-id={@resource.transport_id || ""}
      data-source-resource-source-endpoint-id={@resource.source_endpoint_id || ""}
      data-source-resource-ground-station-id={@resource.ground_station_id || ""}
      data-source-resource-link-id={@resource.link_id || ""}
    >
      <p class="text-xs font-semibold text-base-content">Operational resource context</p>
      <dl class="mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <%= for row <- @resource.rows do %>
          <dt class="hud-label" data-source-resource-row-label={row.key}>{row.label}</dt>
          <dd
            class="break-all font-mono text-base-content"
            data-source-resource-row={row.key}
            data-source-resource-row-value={row.value}
            data-source-resource-row-name={row.display_value}
            data-source-resource-row-status={row.status}
          >
            <.link
              :if={row.href}
              navigate={row.href}
              class="inline-flex items-center gap-1 text-primary hover:underline"
              data-source-resource-link={row.key}
            >
              {row.display_value} <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
            </.link>
            <span :if={!row.href}>{row.display_value}</span>
            <span class="ml-1 font-sans text-[0.65rem] uppercase tracking-normal text-base-content/50">
              {row.status_text}
            </span>
          </dd>
        <% end %>
      </dl>
    </div>
    """
  end

  attr :focus, :map, required: true
  attr :data_sources, :list, required: true
  attr :mission_id, :string, required: true

  def remediation_panel(assigns) do
    assigns =
      assigns
      |> assign(
        :remediation,
        SourceFocusPresentation.remediation(assigns.focus, assigns.data_sources)
      )
      |> assign(:return_href, return_href(assigns.focus, assigns.mission_id))

    ~H"""
    <div
      :if={@remediation}
      id="source-focus-remediation"
      class="mt-3 border-l-2 border-warning/60 pl-3"
      data-source-remediation-kind={@remediation.kind}
      data-source-remediation-target={@remediation.target}
      data-source-remediation-target-id={@remediation.target_id || ""}
    >
      <p class="text-xs font-semibold text-base-content">{@remediation.title}</p>
      <p class="mt-1 text-xs text-base-content/70">{@remediation.detail}</p>
      <div
        :if={@remediation.candidate_rows != []}
        id="source-focus-capability-candidates"
        class="mt-2 space-y-1 text-xs"
      >
        <p class="hud-label">candidate sources</p>
        <div
          :for={candidate <- @remediation.candidate_rows}
          class="flex flex-wrap items-center gap-x-2 gap-y-1 font-mono"
          data-source-capability-candidate={candidate.data_source_id}
          data-source-capability-compatible={text(candidate.compatible?)}
          data-source-capability-missing={candidate.missing_text}
        >
          <span class={[
            "font-semibold",
            candidate.compatible? && "text-success",
            !candidate.compatible? && "text-warning"
          ]}>
            {candidate.status_text}
          </span>
          <span class="text-base-content">{candidate.data_source_id}</span>
          <span class="text-base-content/60">{candidate.reason_text}</span>
        </div>
      </div>
      <dl
        :if={@remediation.capability_rows != []}
        id="source-focus-capability-mismatch"
        class="mt-2 grid grid-cols-[6rem_1fr_1fr] gap-x-2 gap-y-1 text-xs"
      >
        <dt class="hud-label">field</dt>
        <dd class="hud-label">requested</dd>
        <dd class="hud-label">supported</dd>
        <%= for row <- @remediation.capability_rows do %>
          <dt
            class="font-mono text-base-content/70"
            data-source-capability-mismatch-field={row.key}
          >
            {row.label}
          </dt>
          <dd
            class="break-all font-mono text-base-content"
            data-source-capability-mismatch-requested={row.key}
          >
            {row.requested}
          </dd>
          <dd
            class="break-all font-mono text-base-content/70"
            data-source-capability-mismatch-supported={row.key}
          >
            {row.supported}
          </dd>
        <% end %>
      </dl>
      <div class="mt-2 flex flex-wrap gap-2">
        <.button
          :if={@remediation.action == :register_source}
          id="source-focus-register-source"
          size={:xs}
          phx-click="open_register_source"
        >
          <.icon name="hero-plus" class="h-3.5 w-3.5" /> Register Source
        </.button>
        <a
          :if={@remediation.action == :review_binding}
          id="source-focus-review-binding"
          href={"#source-binding-#{@remediation.target_id}"}
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-arrows-right-left" class="h-3.5 w-3.5" /> Review Binding
        </a>
        <a
          :if={@remediation.action == :review_source}
          id="source-focus-review-source"
          href={"#data-source-#{@remediation.target_id}"}
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-server-stack" class="h-3.5 w-3.5" /> Review Source
        </a>
        <.link
          :if={@return_href}
          id="source-focus-dashboard-return"
          navigate={@return_href}
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
          data-source-focus-dashboard-return={@focus.source_dashboard_id}
          data-source-focus-dashboard-return-panel={SourceFocus.return_panel(@focus)}
          data-source-focus-dashboard-return-activity-filter={
            SourceFocus.return_activity_filter(@focus)
          }
          data-source-focus-dashboard-return-activity-event={
            @focus.source_return_activity_event || ""
          }
        >
          <.icon name="hero-arrow-uturn-left" class="h-3.5 w-3.5" /> Return to dashboard readiness
        </.link>
      </div>
    </div>
    """
  end

  attr :focus, :map, required: true
  attr :mission_id, :string, required: true

  def evidence_panel(assigns) do
    assigns =
      assigns
      |> assign(:evidence, SourceFocusPresentation.evidence(assigns.focus))
      |> assign(:return_href, return_href(assigns.focus, assigns.mission_id))

    ~H"""
    <div
      :if={@evidence}
      id="source-focus-evidence"
      class="mt-3 border-l-2 border-info/70 pl-3"
      data-source-evidence-kind={@evidence.kind}
      data-source-evidence-mode={@evidence.mode}
      data-source-evidence-state={@evidence.state}
      data-source-evidence-reason={@evidence.reason}
    >
      <p class="text-xs font-semibold text-base-content">{@evidence.title}</p>
      <p class="mt-1 text-xs text-base-content/70">{@evidence.detail}</p>
      <.link
        :if={@return_href}
        id="source-focus-evidence-dashboard-return"
        navigate={@return_href}
        class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        data-source-focus-dashboard-return={@focus.source_dashboard_id}
        data-source-focus-dashboard-return-panel={SourceFocus.return_panel(@focus)}
        data-source-focus-dashboard-return-activity-filter={
          SourceFocus.return_activity_filter(@focus)
        }
        data-source-focus-dashboard-return-activity-event={
          @focus.source_return_activity_event || ""
        }
      >
        <.icon name="hero-arrow-uturn-left" class="h-3.5 w-3.5" /> Return to dashboard readiness
      </.link>
    </div>
    """
  end

  defp resource_href(_resources, mission_id, :transport_id, transport_id)
       when is_binary(mission_id) and mission_id != "" and is_binary(transport_id) and
              transport_id != "" do
    ~p"/missions/#{mission_id}/comms/transports/#{transport_id}"
  end

  defp resource_href(_resources, mission_id, :source_endpoint_id, source_endpoint_id)
       when is_binary(mission_id) and mission_id != "" and is_binary(source_endpoint_id) and
              source_endpoint_id != "" do
    ~p"/missions/#{mission_id}/comms?#{%{source_endpoint_id: source_endpoint_id}}"
  end

  defp resource_href(
         %{routing_rule: %{routing_rule_id: routing_rule_id}},
         mission_id,
         :link_id,
         _link_assignment_id
       )
       when is_binary(mission_id) and mission_id != "" and is_binary(routing_rule_id) and
              routing_rule_id != "" do
    ~p"/missions/#{mission_id}/comms/routing/#{routing_rule_id}"
  end

  defp resource_href(
         %{ground_station: %{ground_station_id: ground_station_id}},
         mission_id,
         :ground_station_id,
         _ground_station_id
       )
       when is_binary(mission_id) and mission_id != "" and is_binary(ground_station_id) and
              ground_station_id != "" do
    ~p"/missions/#{mission_id}/comms/ground-stations/#{ground_station_id}"
  end

  defp resource_href(_resources, _mission_id, _key, _value), do: nil

  defp return_href(%{source_dashboard_id: dashboard_id} = focus, mission_id)
       when is_binary(dashboard_id) and dashboard_id != "" and is_binary(mission_id) and
              mission_id != "" do
    params =
      %{
        "panel" => SourceFocus.return_panel(focus),
        "activity_filter" => SourceFocus.return_activity_filter(focus),
        "activity_event" => SourceFocus.return_activity_event(focus),
        "refresh_readiness" => SourceFocus.return_refresh_readiness(focus)
      }
      |> compact()

    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{params}"
  end

  defp return_href(_focus, _mission_id), do: nil

  defp compact(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp text(value) when is_boolean(value), do: to_string(value)
end
