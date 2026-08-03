defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextPresentation

  attr :current_mission, :any, default: nil
  attr :spacecraft, :list, required: true
  attr :source_endpoints, :list, default: []
  attr :transports, :list, default: []
  attr :ground_stations, :list, default: []
  attr :link_assignments, :list, default: []
  attr :scheduled_contacts, :list, default: []
  attr :realized_contacts, :list, default: []
  attr :context_spacecraft_id, :string, required: true
  attr :context_scope_kind, :string, default: nil
  attr :context_scope_id, :string, default: nil
  attr :context_scope_ids, :list, default: []
  attr :query, :string, required: true

  def context_selector(assigns) do
    assigns =
      assigns
      |> assign(:context_presentation, DashboardRuntimeContextPresentation.build(assigns))
      |> assign(:context_form, to_form(%{"q" => assigns.query}))

    ~H"""
    <div class="relative min-w-0">
      <div :if={@context_presentation.selected_label} class="mb-3 flex items-center justify-between gap-3">
        <div class="min-w-0">
          <p class="text-[0.62rem] font-semibold uppercase tracking-[0.08em] text-base-content/45">
            Current scope
          </p>
          <span
            id="dashboard-selected-context"
            data-dashboard-selected-context-kind={@context_presentation.selected_scope_kind || ""}
            data-dashboard-selected-context-id={@context_presentation.selected_scope_id || ""}
            data-dashboard-selected-context-ids={Enum.join(@context_presentation.selected_scope_ids, ",")}
            class="badge badge-primary badge-outline badge-sm mt-1 max-w-full truncate font-mono"
          >
            {@context_presentation.selected_label}
          </span>
        </div>
        <.button variant={:ghost} size={:xs} phx-click="clear_context" aria-label="Clear context">
          <.icon name="hero-x-mark" class="h-3 w-3" />
        </.button>
      </div>
      <p class="mb-1.5 text-[0.62rem] font-semibold uppercase tracking-[0.08em] text-base-content/45">
        Find operational context
      </p>
      <.form
        for={@context_form}
        id="context-search-form"
        phx-change="context_search"
        onsubmit="return false"
        class="w-full"
      >
        <.input
          field={@context_form[:q]}
          id="context-search"
          type="search"
          placeholder="Find mission, spacecraft, contact, source, transport, ground, or link"
          compact
          phx-debounce="150"
        />
      </.form>
      <ul
        :if={@query != ""}
        class="absolute left-0 right-0 top-full z-[var(--z-popover)] mt-1 max-h-60 overflow-y-auto rounded border border-primary/20 bg-base-200 p-1 shadow-lg"
      >
        <li :for={action <- @context_presentation.batch_actions}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind={action.scope_kind}
            phx-value-scope-ids={action.scope_ids_text}
            data-dashboard-context-batch-result={action.scope_kind}
            data-dashboard-context-batch-count={action.count}
            data-dashboard-context-batch-ids={action.scope_ids_text}
            class="mb-1 w-full rounded border border-primary/20 bg-primary/10 px-2 py-1 text-left text-sm hover:bg-primary/20"
          >
            <.icon name="hero-squares-2x2" class="mr-1 inline h-3.5 w-3.5" />
            {action.label}
          </button>
        </li>
        <li :if={@context_presentation.mission}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind="mission"
            phx-value-scope-id={@context_presentation.mission.id}
            class="w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          >
            {@context_presentation.mission.label}
            <span class="ml-2 font-mono text-xs text-base-content/60">mission</span>
          </button>
        </li>
        <li :for={sc <- @context_presentation.spacecraft}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind="spacecraft"
            phx-value-scope-id={sc.spacecraft_id}
            phx-value-spacecraft-id={sc.spacecraft_id}
            class="w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          >
            {sc.display_name}
            <span :if={sc.scid} class="ml-2 font-mono text-xs text-base-content/60">{sc.scid}</span>
          </button>
        </li>
        <li :for={contact <- @context_presentation.contacts}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind="contact"
            phx-value-scope-id={contact.id}
            data-dashboard-context-result="contact"
            data-dashboard-context-contact-kind={contact.kind}
            data-dashboard-context-contact-id={contact.id}
            class="w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          >
            {contact.label}
            <span class="ml-2 font-mono text-xs text-base-content/60">{contact.kind}</span>
          </button>
        </li>
        <li :for={source_endpoint <- @context_presentation.source_endpoints}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind="source_endpoint"
            phx-value-scope-id={source_endpoint.id}
            data-dashboard-context-result="source_endpoint"
            data-dashboard-context-source-endpoint-id={source_endpoint.id}
            class="w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          >
            {source_endpoint.label}
            <span class="ml-2 font-mono text-xs text-base-content/60">source endpoint</span>
          </button>
        </li>
        <li :for={ground_station <- @context_presentation.ground_stations}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind="ground_station"
            phx-value-scope-id={ground_station.id}
            data-dashboard-context-result="ground_station"
            data-dashboard-context-ground-station-id={ground_station.id}
            class="w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          >
            {ground_station.label}
            <span class="ml-2 font-mono text-xs text-base-content/60">ground station</span>
          </button>
        </li>
        <li :for={transport <- @context_presentation.transports}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind="transport"
            phx-value-scope-id={transport.id}
            data-dashboard-context-result="transport"
            data-dashboard-context-transport-id={transport.id}
            class="w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          >
            {transport.label}
            <span class="ml-2 font-mono text-xs text-base-content/60">transport</span>
          </button>
        </li>
        <li :for={link <- @context_presentation.links}>
          <button
            type="button"
            phx-click="set_context"
            phx-value-scope-kind="link"
            phx-value-scope-id={link.id}
            data-dashboard-context-result="link"
            data-dashboard-context-link-id={link.id}
            class="w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          >
            {link.label}
            <span class="ml-2 font-mono text-xs text-base-content/60">link</span>
          </button>
        </li>
        <li
          :if={Map.get(@context_presentation, :no_matches?)}
          class="px-2 py-1 text-sm text-base-content/60"
        >
          No context matches.
        </li>
      </ul>
    </div>
    """
  end
end
