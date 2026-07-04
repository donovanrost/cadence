defmodule CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionPresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs
  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation
  alias CadenceWeb.OpsDashboardShowLive.HealthEvidenceActivity

  alias Cadence.Dashboards.DashboardAction

  @evidence_data_link_targets %{
    raw_evidence: :raw_evidence,
    telemetry_sample: :telemetry_sample,
    limit_event: :limit_event,
    limit_definition: :limit_definition,
    limit_definition_interval: :limit_definition_interval,
    limit_definition_lifecycle_event: :limit_definition_lifecycle_event,
    mission_event: :mission_event,
    operational_event: :operational_event,
    binding_set_interval: :binding_set_interval,
    application_binding_interval: :application_binding_interval,
    catalog_revision_interval: :catalog_revision_interval,
    source_binding_interval: :source_binding_interval,
    transport_execution_interval: :transport_execution_interval,
    transport_connection_state_interval: :transport_connection_state_interval,
    ground_station_connection_state_interval: :ground_station_connection_state_interval,
    ground_station_antenna_pointing_state_interval:
      :ground_station_antenna_pointing_state_interval,
    link_rf_lock_state_interval: :link_rf_lock_state_interval,
    link_frame_sync_state_interval: :link_frame_sync_state_interval,
    source_health_event: :source_health_event,
    source_watermark_event: :source_watermark_event,
    source_binding_event: :source_binding_event,
    telemetry_revision_decision_event: :telemetry_revision_decision_event,
    telemetry_backfill_lifecycle_event: :telemetry_backfill_lifecycle_event,
    contact: :contact,
    scheduled_contact: :contact,
    realized_contact: :contact
  }

  attr :inspector, :map, required: true
  attr :mission_id, :string, required: true
  attr :dashboard_document, :any, required: true
  attr :dashboard_current_path, :string, required: true
  attr :dashboard_lifecycle_events, :list, required: true

  def evidence_panel(assigns) do
    assigns =
      assign(
        assigns,
        :health_activity,
        HealthEvidenceActivity.build(assigns.inspector, assigns.dashboard_lifecycle_events)
      )
      |> assign(
        :presented_links,
        DataLinkPresentation.evidence(
          Map.get(assigns.inspector, :links, []),
          assigns.inspector
        )
      )

    ~H"""
    <section
      id="dashboard-evidence-inspector"
      data-evidence-kind={text_value(@inspector.kind)}
      data-evidence-subject={@inspector.subject || ""}
      data-evidence-status={@inspector.status_text || ""}
      class="space-y-4"
    >
      <div class="space-y-1">
        <div class="flex items-center gap-2">
          <span class="badge badge-xs badge-outline">{@inspector.kind_text}</span>
          <span class="badge badge-xs">{@inspector.status_text}</span>
        </div>
        <p :if={@inspector.message} class="text-sm text-base-content/70">
          {@inspector.message}
        </p>
      </div>

      <div class="grid gap-2">
        <button
          id="dashboard-evidence-copy-link"
          type="button"
          phx-hook="ClipboardButton"
          data-clipboard-text={@dashboard_current_path}
          class="btn btn-sm btn-outline justify-start"
        >
          <.icon name="hero-link" class="h-4 w-4" /> Copy evidence link
        </button>
        <.dashboard_actions
          actions={evidence_actions(@mission_id, @inspector, @dashboard_document)}
        />
        <.link
          :if={@health_activity.render?}
          id="dashboard-evidence-health-activity-link"
          navigate={
            ActivityNavigation.link(
              @dashboard_current_path,
              :health_snapshots,
              @health_activity.event
            )
          }
          class="btn btn-sm btn-outline justify-start"
          data-dashboard-health-activity-link={@health_activity.event_id}
          data-dashboard-health-activity-snapshot-id={@health_activity.snapshot_id}
        >
          <.icon name="hero-bookmark-square" class="h-4 w-4" /> Open activity
        </.link>
      </div>

      <.evidence_rows
        :if={@inspector.subject_rows != []}
        title="Subject"
        rows={@inspector.subject_rows}
      />

      <.evidence_rows
        :if={@inspector.detail_rows != []}
        title="Details"
        rows={@inspector.detail_rows}
      />

      <section :if={@inspector.evidence != []} class="space-y-2" data-evidence-refs>
        <h3 class="hud-label">Evidence</h3>
        <div class="space-y-1">
          <.evidence_ref_card
            :for={evidence <- @inspector.evidence}
            evidence={evidence}
            inspector={@inspector}
          />
        </div>
      </section>
      <p
        :if={@inspector.evidence == []}
        class="rounded border border-base-300/70 bg-base-100/40 px-2 py-2 text-xs text-base-content/60"
        data-evidence-empty="refs"
      >
        No evidence references were provided for this item.
      </p>

      <section :if={@presented_links != []} class="space-y-2" data-evidence-links>
        <h3 class="hud-label">Data Links</h3>
        <div class="space-y-1">
          <button
            :for={link <- @presented_links}
            type="button"
            phx-click="open_data_link"
            {DataLinkAttrs.open(link)}
            class="grid w-full grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100"
            data-evidence-link-target={link.target_text}
            data-evidence-link-id={link.target_id || ""}
            data-evidence-link-ref={link.link_id || ""}
          >
            <span class="text-base-content/60">{link.target_text}</span>
            <span class="font-mono text-base-content break-all">{link.target_id}</span>
            <span class="text-base-content/60">Label</span>
            <span class="text-base-content break-all">{link.label}</span>
          </button>
        </div>
      </section>
      <p
        :if={@presented_links == []}
        class="rounded border border-base-300/70 bg-base-100/40 px-2 py-2 text-xs text-base-content/60"
        data-evidence-empty="links"
      >
        No data links were provided for this item.
      </p>
    </section>
    """
  end

  attr :evidence, :map, required: true
  attr :inspector, :map, required: true

  defp evidence_ref_card(assigns) do
    assigns = assign(assigns, :data_link, evidence_data_link(assigns.evidence))

    ~H"""
    <button
      :if={@data_link}
      type="button"
      phx-click="open_data_link"
      {DataLinkAttrs.open(@data_link, context_fallback: evidence_ref_context(@inspector))}
      class="grid w-full grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100"
      data-evidence-ref-kind={@evidence.kind_text}
      data-evidence-ref-id={@evidence.id || ""}
      data-evidence-ref-link-target={@data_link.target}
    >
      <span class="text-base-content/60">Kind</span>
      <span class="font-mono text-base-content break-all">{@evidence.kind_text}</span>
      <span class="text-base-content/60">ID</span>
      <span class="font-mono text-base-content break-all">{@evidence.id}</span>
      <span class="text-base-content/60">Source</span>
      <span class="font-mono text-base-content break-all">{@evidence.source_text}</span>
      <span class="text-base-content/60">Confidence</span>
      <span class="font-mono text-base-content break-all">{@evidence.confidence_text}</span>
      <span class="text-base-content/60">Observed</span>
      <span class="font-mono text-base-content break-all">{@evidence.observed_at_text}</span>
    </button>
    <div
      :if={!@data_link}
      class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-xs"
      data-evidence-ref-kind={@evidence.kind_text}
      data-evidence-ref-id={@evidence.id || ""}
    >
      <span class="text-base-content/60">Kind</span>
      <span class="font-mono text-base-content break-all">{@evidence.kind_text}</span>
      <span class="text-base-content/60">ID</span>
      <span class="font-mono text-base-content break-all">{@evidence.id}</span>
      <span class="text-base-content/60">Source</span>
      <span class="font-mono text-base-content break-all">{@evidence.source_text}</span>
      <span class="text-base-content/60">Confidence</span>
      <span class="font-mono text-base-content break-all">{@evidence.confidence_text}</span>
      <span class="text-base-content/60">Observed</span>
      <span class="font-mono text-base-content break-all">{@evidence.observed_at_text}</span>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true

  defp evidence_rows(assigns) do
    ~H"""
    <section class="space-y-2">
      <h3 class="hud-label">{@title}</h3>
      <dl class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <%= for row <- @rows do %>
          <dt class="text-base-content/60">{row.label}</dt>
          <dd
            class="font-mono text-base-content break-all"
            data-evidence-subject-field={row.label}
            data-evidence-detail={row.label}
          >
            {row.value}
          </dd>
        <% end %>
      </dl>
    </section>
    """
  end

  attr :actions, :list, required: true

  defp dashboard_actions(assigns) do
    ~H"""
    <.link
      :for={%DashboardAction{} = action <- DashboardActionPresentation.visible(@actions)}
      id={action.action_id}
      navigate={action.route}
      class="btn btn-sm btn-outline w-full justify-start"
      data-dashboard-action={action.action_id}
      data-dashboard-action-kind={Atom.to_string(action.kind)}
      data-dashboard-action-target={Atom.to_string(action.target)}
      data-dashboard-action-source={Atom.to_string(action.source)}
      data-dashboard-action-presentation={Atom.to_string(action.presentation)}
    >
      <.icon name={DashboardActionPresentation.icon(action)} class="h-4 w-4" /> {action.label}
    </.link>
    """
  end

  defp evidence_actions(mission_id, inspector, dashboard_document) do
    DashboardActionPresentation.for_inspector(
      inspector,
      mission_id,
      :evidence_panel,
      dashboard_document
    )
  end

  defp text_value(nil), do: ""
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)

  defp evidence_ref_context(inspector) when is_map(inspector) do
    rows = Map.get(inspector, :subject_rows, []) ++ Map.get(inspector, :detail_rows, [])

    %{
      realm: evidence_row_value(rows, "Realm") || evidence_row_value(rows, "Data realm"),
      data_view: evidence_row_value(rows, "Data view"),
      data_source_id: evidence_row_value(rows, "Data source"),
      source_binding_id: evidence_row_value(rows, "Source binding"),
      time_mode: evidence_row_value(rows, "Time mode"),
      time_axis: evidence_row_value(rows, "Time axis"),
      replay_run_id: evidence_row_value(rows, "Replay run")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp evidence_ref_context(_inspector), do: %{}

  defp evidence_row_value(rows, label) do
    case Enum.find_value(rows, fn
           %{label: ^label, value: value} -> value
           %{"label" => ^label, "value" => value} -> value
           _row -> nil
         end) do
      nil -> nil
      value -> text_value(value)
    end
  end

  defp evidence_data_link(evidence) do
    with target when is_atom(target) <- evidence_target(evidence),
         id when is_binary(id) and id != "" <- evidence_value(evidence, :id) do
      %{
        link_id: "evidence-ref:#{Atom.to_string(target)}:#{id}",
        label: evidence_label(target),
        target: target,
        target_text: target |> Atom.to_string() |> String.replace("_", " "),
        target_id: id,
        context: %{}
      }
    else
      _missing -> nil
    end
  end

  defp evidence_target(evidence) do
    kind = evidence_kind(evidence)

    Map.get(@evidence_data_link_targets, kind) ||
      direct_operational_interval_target(kind, evidence)
  end

  defp direct_operational_interval_target(:operational_interval, evidence) do
    if evidence_kind(evidence, :confidence) == :direct, do: :operational_event
  end

  defp direct_operational_interval_target(_kind, _evidence), do: nil

  defp evidence_kind(evidence, key \\ :kind) do
    evidence
    |> evidence_value(key)
    |> normalize_evidence_atom()
  end

  defp evidence_value(evidence, key) when is_map(evidence) and is_atom(key) do
    Map.get(evidence, key, Map.get(evidence, Atom.to_string(key)))
  end

  defp evidence_value(_evidence, _key), do: nil

  defp normalize_evidence_atom(value) when is_atom(value), do: value

  defp normalize_evidence_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(" ", "_")
    |> String.replace("-", "_")
    |> evidence_atom()
  end

  defp normalize_evidence_atom(_value), do: nil

  defp evidence_atom("raw_evidence"), do: :raw_evidence
  defp evidence_atom("telemetry_sample"), do: :telemetry_sample
  defp evidence_atom("limit_event"), do: :limit_event
  defp evidence_atom("limit_definition"), do: :limit_definition
  defp evidence_atom("limit_definition_interval"), do: :limit_definition_interval

  defp evidence_atom("limit_definition_lifecycle_event"),
    do: :limit_definition_lifecycle_event

  defp evidence_atom("mission_event"), do: :mission_event
  defp evidence_atom("operational_event"), do: :operational_event
  defp evidence_atom("operational_interval"), do: :operational_interval
  defp evidence_atom("binding_set_interval"), do: :binding_set_interval
  defp evidence_atom("application_binding_interval"), do: :application_binding_interval
  defp evidence_atom("catalog_revision_interval"), do: :catalog_revision_interval
  defp evidence_atom("source_binding_interval"), do: :source_binding_interval
  defp evidence_atom("transport_execution_interval"), do: :transport_execution_interval

  defp evidence_atom("transport_connection_state_interval"),
    do: :transport_connection_state_interval

  defp evidence_atom("ground_station_connection_state_interval"),
    do: :ground_station_connection_state_interval

  defp evidence_atom("ground_station_antenna_pointing_state_interval"),
    do: :ground_station_antenna_pointing_state_interval

  defp evidence_atom("link_rf_lock_state_interval"), do: :link_rf_lock_state_interval
  defp evidence_atom("link_frame_sync_state_interval"), do: :link_frame_sync_state_interval

  defp evidence_atom("source_health_event"), do: :source_health_event
  defp evidence_atom("source_watermark_event"), do: :source_watermark_event
  defp evidence_atom("source_binding_event"), do: :source_binding_event
  defp evidence_atom("telemetry_revision_decision_event"), do: :telemetry_revision_decision_event

  defp evidence_atom("telemetry_backfill_lifecycle_event"),
    do: :telemetry_backfill_lifecycle_event

  defp evidence_atom("contact"), do: :contact
  defp evidence_atom("scheduled_contact"), do: :scheduled_contact
  defp evidence_atom("realized_contact"), do: :realized_contact
  defp evidence_atom(_value), do: nil

  defp evidence_label(target) do
    target
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
