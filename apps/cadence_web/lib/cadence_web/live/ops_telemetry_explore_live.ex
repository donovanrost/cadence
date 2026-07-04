defmodule CadenceWeb.OpsTelemetryExploreLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources}
  alias Cadence.Telemetry.SelectionPolicy

  @default_limit 100
  @max_limit 1_000
  @query_params [
    "point_id",
    "spacecraft_id",
    "time_mode",
    "from",
    "to",
    "order",
    "limit",
    "selection_view",
    "validity_state",
    "realm",
    "logical_source",
    "data_source_id",
    "source_binding_id",
    "source_dashboard_id",
    "sample_id",
    "selected_time"
  ]

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    points = Cadence.list_ops_telemetry_points(scope.organization_id, mission.mission_id)
    spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)
    data_sources = DataSources.list_data_sources(scope.organization_id, mission.mission_id)
    data_bindings = DataSources.list_data_bindings(scope.organization_id, mission.mission_id)
    data_realms = Cadence.list_dashboard_data_realms(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Telemetry Explore")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:points, points)
     |> assign(:spacecraft, spacecraft)
     |> assign(:data_sources, data_sources)
     |> assign(:data_bindings, data_bindings)
     |> assign(:data_realms, data_realms)
     |> assign(:explore_context, explore_context(%{}))
     |> assign(:filter_form, to_form(%{}, as: :explore))
     |> assign(:point, nil)
     |> assign(:samples, [])
     |> assign(:selected_sample, nil)
     |> assign(:selected_sample_state, "none")
     |> assign(:source_context, source_context(explore_context(%{}), [], []))
     |> assign(:history_diagnostics, history_diagnostics([], %{}, explore_context(%{}), false))
     |> assign(:investigation_path, telemetry_explore_path(mission.mission_id, %{}))
     |> assign(
       :investigation_fingerprint,
       investigation_fingerprint(telemetry_explore_path(mission.mission_id, %{}))
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    context = explore_context(params)
    canonical_query = investigation_query(context)

    if incoming_query(params) != canonical_query do
      {:noreply,
       push_patch(socket,
         to: telemetry_explore_path(mission.mission_id, canonical_query),
         replace: true
       )}
    else
      point = find_point(socket.assigns.points, context.point_id)
      {samples, diagnostics} = load_samples(scope.organization_id, mission.mission_id, context)
      selected_sample = selected_sample(samples, context.sample_id)
      selected_sample_state = selected_sample_state(context, selected_sample)

      source_context =
        source_context(context, socket.assigns.data_sources, socket.assigns.data_bindings)

      investigation_path = telemetry_explore_path(mission.mission_id, canonical_query)

      {:noreply,
       socket
       |> assign(:explore_context, context)
       |> assign(:filter_form, to_form(filter_params(context), as: :explore))
       |> assign(:point, point)
       |> assign(:samples, samples)
       |> assign(:selected_sample, selected_sample)
       |> assign(:selected_sample_state, selected_sample_state)
       |> assign(:source_context, source_context)
       |> assign(:history_diagnostics, diagnostics)
       |> assign(:investigation_path, investigation_path)
       |> assign(:investigation_fingerprint, investigation_fingerprint(investigation_path))}
    end
  end

  @impl true
  def handle_event("apply_filters", %{"explore" => params}, socket) do
    mission_id = socket.assigns.current_mission.mission_id
    query = params |> normalize_filter_params() |> explore_context() |> investigation_query()

    {:noreply, push_patch(socket, to: telemetry_explore_path(mission_id, query))}
  end

  def handle_event("apply_filters", _params, socket), do: {:noreply, socket}

  def handle_event("clear_selected_sample", _params, socket) do
    mission_id = socket.assigns.current_mission.mission_id

    query =
      socket.assigns.explore_context
      |> Map.merge(%{sample_id: nil, selected_time: nil, source_dashboard_id: nil})
      |> investigation_query()

    {:noreply, push_patch(socket, to: telemetry_explore_path(mission_id, query))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="ops-telemetry-explore-page"
      class="flex-1 overflow-y-auto"
      data-explore-source-state={@source_context.state}
      data-explore-data-source={@source_context.data_source_id || ""}
      data-explore-source-binding={@source_context.source_binding_id || ""}
      data-explore-logical-source={@source_context.logical_source || ""}
      data-explore-realm={@source_context.realm || ""}
      data-explore-selected-sample-state={@selected_sample_state}
      data-explore-selected-sample-id={@explore_context.sample_id || ""}
    >
      <div class="mx-auto max-w-7xl px-6 py-8">
        <div class="flex flex-col gap-3 border-b border-base-300/60 pb-5 md:flex-row md:items-end md:justify-between">
          <div>
            <div class="flex flex-wrap items-center gap-2">
              <h1 class="text-lg font-semibold text-base-content">Telemetry Explore</h1>
              <span :if={@explore_context.realm} class="badge badge-xs badge-outline">
                {@explore_context.realm}
              </span>
              <span :if={@explore_context.time_mode} class="badge badge-xs">
                {@explore_context.time_mode}
              </span>
            </div>
            <p class="mt-1 font-mono text-xs text-base-content/60">
              {@explore_context.point_id || "No point selected"}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              id="telemetry-explore-copy-link"
              type="button"
              phx-hook="ClipboardButton"
              data-clipboard-text={@investigation_path}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-link" class="h-4 w-4" /> Copy link
            </button>
            <.link
              :if={@explore_context.source_dashboard_id}
              id="telemetry-explore-back-to-dashboard"
              navigate={dashboard_path(@current_mission.mission_id, @explore_context.source_dashboard_id)}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" /> Dashboard
            </.link>
          </div>
        </div>

        <.form
          for={@filter_form}
          id="telemetry-explore-filter-form"
          phx-submit="apply_filters"
          class="mt-5 border border-base-300/70 bg-base-100/40 p-4"
        >
          <input type="hidden" name="explore[source_dashboard_id]" value={@explore_context.source_dashboard_id || ""} />
          <input type="hidden" name="explore[sample_id]" value={@explore_context.sample_id || ""} />
          <input type="hidden" name="explore[selected_time]" value={@explore_context.selected_time || ""} />

          <div class="grid gap-3 lg:grid-cols-[minmax(12rem,1.25fr)_minmax(10rem,1fr)_9rem_10rem_10rem_8rem_auto] lg:items-end">
            <.input
              field={@filter_form[:point_id]}
              type="select"
              label="Point"
              options={point_options(@points, @explore_context.point_id)}
              compact
            />
            <.input
              field={@filter_form[:spacecraft_id]}
              type="select"
              label="Spacecraft"
              options={spacecraft_options(@spacecraft)}
              compact
            />
            <.input
              field={@filter_form[:time_mode]}
              type="select"
              label="Window"
              options={time_mode_options()}
              compact
            />
            <.input field={@filter_form[:from]} type="text" label="From" compact />
            <.input field={@filter_form[:to]} type="text" label="To" compact />
            <.input
              field={@filter_form[:order]}
              type="select"
              label="Order"
              options={order_options()}
              compact
            />
            <div class="grid grid-cols-[minmax(0,1fr)_auto] gap-2">
              <.input field={@filter_form[:limit]} type="number" label="Limit" compact min="1" max="1000" />
              <.button id="telemetry-explore-apply-filters" type="submit" size={:sm}>
                <.icon name="hero-arrow-path" class="h-4 w-4" /> Load
              </.button>
            </div>
          </div>
          <div class="mt-3 grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <.input
              field={@filter_form[:realm]}
              type="select"
              label="Realm"
              options={realm_options(@data_realms, @data_bindings, @explore_context.realm)}
              compact
            />
            <.input
              field={@filter_form[:logical_source]}
              type="select"
              label="Logical Source"
              options={logical_source_options()}
              compact
            />
            <.input
              field={@filter_form[:data_source_id]}
              type="select"
              label="Data Source"
              options={data_source_options(@data_sources, @data_bindings, @explore_context)}
              compact
            />
            <.input
              field={@filter_form[:source_binding_id]}
              type="select"
              label="Source Binding"
              options={source_binding_options(@data_bindings, @explore_context)}
              compact
            />
            <.input
              field={@filter_form[:selection_view]}
              type="select"
              label="Selection View"
              options={selection_view_options()}
              compact
            />
            <.input
              field={@filter_form[:validity_state]}
              type="select"
              label="Validity"
              options={validity_state_options()}
              compact
            />
          </div>
        </.form>

        <div
          id="telemetry-explore-investigation-summary"
          class="mt-3 flex flex-wrap items-center gap-2 text-xs text-base-content/60"
          data-investigation-path={@investigation_path}
          data-investigation-fingerprint={@investigation_fingerprint}
        >
          <span class="hud-label">Investigation</span>
          <span class="font-mono text-base-content/70">{@investigation_fingerprint}</span>
          <span class="font-mono break-all">{@investigation_path}</span>
        </div>

        <div
          :if={@selected_sample_state == "missing"}
          id="telemetry-explore-selected-sample-status"
          class="mt-3 flex items-start gap-3 border border-warning/30 bg-warning/10 px-4 py-3 text-sm"
          data-explore-selected-sample-state={@selected_sample_state}
          data-explore-selected-sample-id={@explore_context.sample_id || ""}
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 h-4 w-4 shrink-0" />
          <div class="min-w-0">
            <p class="font-semibold">Selected sample is outside the current result set</p>
            <p class="mt-1 break-all font-mono text-xs text-base-content/60">
              {@explore_context.sample_id}
            </p>
          </div>
        </div>

        <div class="mt-6 grid gap-4 xl:grid-cols-[22rem_minmax(0,1fr)]">
          <aside class="space-y-4">
            <section
              id="telemetry-explore-point-card"
              class="border border-base-300/70 bg-base-100/40 p-4"
            >
              <h2 class="hud-label">Point</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <dt class="text-base-content/60">Point</dt>
                <dd class="font-mono text-base-content break-all" data-explore-point-field="Point">
                  {@explore_context.point_id || "none"}
                </dd>
                <dt :if={@point} class="text-base-content/60">Packet</dt>
                <dd
                  :if={@point}
                  class="font-mono text-base-content break-all"
                  data-explore-point-field="Packet"
                >
                  {@point.packet_name}
                </dd>
                <dt :if={@point} class="text-base-content/60">Field</dt>
                <dd
                  :if={@point}
                  class="font-mono text-base-content break-all"
                  data-explore-point-field="Field"
                >
                  {@point.field_name}
                </dd>
                <dt :if={@point && @point.unit} class="text-base-content/60">Unit</dt>
                <dd
                  :if={@point && @point.unit}
                  class="font-mono text-base-content break-all"
                  data-explore-point-field="Unit"
                >
                  {@point.unit}
                </dd>
                <dt :if={@point && @point.description} class="text-base-content/60">
                  Description
                </dt>
                <dd
                  :if={@point && @point.description}
                  class="text-base-content break-words"
                  data-explore-point-field="Description"
                >
                  {@point.description}
                </dd>
              </dl>
              <p :if={!@point && @explore_context.point_id} class="mt-3 text-sm text-warning">
                Point is not present in the active operator point catalog.
              </p>
            </section>

            <section
              :if={@selected_sample}
              id="telemetry-explore-selected-sample-card"
              class="border border-primary/30 bg-base-100/50 p-4"
              data-explore-selected-sample-card={@selected_sample.sample_id}
            >
              <div class="flex items-center justify-between gap-3">
                <h2 class="hud-label">Selected Sample</h2>
                <div class="flex items-center gap-2">
                  <span class="badge badge-xs badge-outline">
                    {validity_state_label(@selected_sample)}
                  </span>
                  <button
                    id="telemetry-explore-clear-selected-sample"
                    type="button"
                    phx-click="clear_selected_sample"
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon name="hero-x-mark" class="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <%= for row <- sample_provenance_rows(@selected_sample) do %>
                  <dt class="text-base-content/60">{row.label}</dt>
                  <dd
                    class="font-mono text-base-content break-all"
                    data-explore-selected-provenance={row.label}
                  >
                    {row.value}
                  </dd>
                <% end %>
              </dl>
              <div :if={dashboard_sample_href(@current_mission.mission_id, @explore_context, @selected_sample)} class="mt-3">
                <.link
                  id="telemetry-explore-open-selected-in-dashboard"
                  navigate={dashboard_sample_href(@current_mission.mission_id, @explore_context, @selected_sample)}
                  class="btn btn-xs btn-outline w-full justify-start"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" /> Open in dashboard
                </.link>
              </div>
            </section>

            <section
              id="telemetry-explore-source-card"
              class={[
                "border bg-base-100/40 p-4",
                @source_context.state == "matched" && "border-primary/30",
                @source_context.state == "missing" && "border-warning/30",
                @source_context.state == "none" && "border-base-300/70"
              ]}
              data-explore-source-state={@source_context.state}
              data-explore-data-source={@source_context.data_source_id || ""}
              data-explore-source-binding={@source_context.source_binding_id || ""}
              data-explore-logical-source={@source_context.logical_source || ""}
              data-explore-realm={@source_context.realm || ""}
              data-explore-matched-data-source={@source_context.matched_data_source_id || ""}
              data-explore-matched-source-binding={@source_context.matched_source_binding_id || ""}
            >
              <h2 class="hud-label">Source Context</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <%= for row <- source_context_rows(@source_context, @samples) do %>
                  <dt class="text-base-content/60">{row.label}</dt>
                  <dd
                    class="font-mono text-base-content break-all"
                    data-explore-source={row.label}
                  >
                    {row.value}
                  </dd>
                <% end %>
              </dl>
            </section>

            <section
              id="telemetry-explore-context-card"
              class="border border-base-300/70 bg-base-100/40 p-4"
            >
              <h2 class="hud-label">Context</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <%= for row <- context_rows(@explore_context) do %>
                  <dt class="text-base-content/60">{row.label}</dt>
                  <dd
                    class="font-mono text-base-content break-all"
                    data-explore-context={row.label}
                  >
                    {row.value}
                  </dd>
                <% end %>
              </dl>
            </section>

            <section
              id="telemetry-explore-diagnostics-card"
              class="border border-base-300/70 bg-base-100/40 p-4"
            >
              <h2 class="hud-label">Read Diagnostics</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <%= for row <- diagnostics_rows(@history_diagnostics) do %>
                  <dt class="text-base-content/60">{row.label}</dt>
                  <dd class="font-mono text-base-content break-all" data-explore-diagnostics={row.label}>
                    {row.value}
                  </dd>
                <% end %>
              </dl>
            </section>
          </aside>

          <section class="min-w-0 border border-base-300/70 bg-base-100/40">
            <header class="flex items-center justify-between gap-3 border-b border-base-300/70 px-4 py-3">
              <div>
                <h2 class="hud-label">Samples</h2>
                <p class="mt-1 text-xs text-base-content/60">
                  {length(@samples)} rows, {order_label(@explore_context.order)}
                </p>
              </div>
              <span
                :if={@explore_context.sample_id}
                class="badge badge-xs badge-outline font-mono"
                data-explore-selected-sample={@explore_context.sample_id}
                data-explore-selected-sample-state={@selected_sample_state}
              >
                {@explore_context.sample_id}
              </span>
            </header>

            <div class="overflow-x-auto">
              <table id="telemetry-explore-samples" class="table table-xs">
                <thead>
                  <tr>
                    <th>Receipt</th>
                    <th>Generation</th>
                    <th>Spacecraft</th>
                    <th>Engineering</th>
                    <th>Raw</th>
                    <th>Quality</th>
                    <th>Validity</th>
                    <th>Source</th>
                    <th>Evidence</th>
                    <th>Packet</th>
                    <th>Definition</th>
                    <th>Sample</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@samples == []}>
                    <td colspan="13" class="py-6 text-center text-sm text-base-content/60">
                      {empty_samples_message(@history_diagnostics)}
                    </td>
                  </tr>
                  <%= for sample <- @samples do %>
                    <tr
                      id={"telemetry-explore-sample-#{sample.sample_id}"}
                      class={[
                        sample.sample_id == @explore_context.sample_id &&
                          "bg-primary/10 outline outline-1 outline-primary/40"
                      ]}
                      data-explore-sample-id={sample.sample_id}
                      data-explore-selected={sample.sample_id == @explore_context.sample_id}
                    >
                      <td class="font-mono">{format_datetime(sample.receipt_time)}</td>
                      <td class="font-mono">{format_datetime(sample.generation_time)}</td>
                      <td class="font-mono">{sample.spacecraft_id || "mission"}</td>
                      <td class="font-mono">{format_value(sample.engineering_value)}</td>
                      <td class="font-mono">{format_value(sample.raw_value)}</td>
                      <td>{sample.quality_state}</td>
                      <td>
                        <span class="badge badge-xs badge-outline">
                          {validity_state_label(sample)}
                        </span>
                      </td>
                      <td
                        class="font-mono break-all"
                        data-explore-sample-source={sample_source_ref(sample)}
                      >
                        {sample_source_ref(sample)}
                      </td>
                      <td
                        class="font-mono break-all"
                        data-explore-sample-evidence={sample.evidence_id || ""}
                      >
                        {sample.evidence_id || "none"}
                      </td>
                      <td
                        class="font-mono break-all"
                        data-explore-sample-packet={sample.packet_id || ""}
                      >
                        {sample.packet_id || "none"}
                      </td>
                      <td
                        class="font-mono break-all"
                        data-explore-sample-definition={sample.packet_definition_id || ""}
                      >
                        {packet_definition_ref(sample)}
                      </td>
                      <td class="font-mono break-all">{sample.sample_id}</td>
                      <td class="text-right">
                        <.link
                          :if={dashboard_sample_href(@current_mission.mission_id, @explore_context, sample)}
                          navigate={dashboard_sample_href(@current_mission.mission_id, @explore_context, sample)}
                          class="btn btn-ghost btn-xs"
                          title="Open in dashboard"
                          data-explore-open-sample={sample.sample_id}
                        >
                          <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
                        </.link>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp explore_context(params) do
    %{
      point_id: text_param(params["point_id"]),
      sample_id: text_param(params["sample_id"]),
      spacecraft_id: text_param(params["spacecraft_id"]),
      time_mode: normalize_time_mode(params["time_mode"]),
      from: effective_from(params),
      to: effective_to(params),
      from_text: text_param(params["from"]),
      to_text: text_param(params["to"]),
      realm: text_param(params["realm"]),
      logical_source: parse_logical_source(params["logical_source"]),
      logical_source_text: logical_source_text(params["logical_source"]),
      data_source_id: text_param(params["data_source_id"]),
      source_binding_id: text_param(params["source_binding_id"]),
      source_dashboard_id: text_param(params["source_dashboard_id"]),
      selected_time: text_param(params["selected_time"]),
      limit: parse_limit(params["limit"]),
      limit_text: limit_text(params["limit"]),
      order: parse_order(params["order"]),
      order_text: order_text(params["order"]),
      selection_view: parse_selection_view(params["selection_view"]),
      selection_view_text: selection_view_text(params["selection_view"]),
      validity_state: parse_validity_state(params["validity_state"]),
      validity_state_text: validity_state_text(params["validity_state"])
    }
  end

  defp find_point(_points, nil), do: nil
  defp find_point(points, point_id), do: Enum.find(points, &(&1.point_id == point_id))

  defp selected_sample(_samples, nil), do: nil
  defp selected_sample(samples, sample_id), do: Enum.find(samples, &(&1.sample_id == sample_id))

  defp selected_sample_state(%{sample_id: nil}, _selected_sample), do: "none"
  defp selected_sample_state(_context, nil), do: "missing"
  defp selected_sample_state(_context, _selected_sample), do: "matched"

  defp source_context(context, sources, bindings) do
    context
    |> default_source_context()
    |> resolve_source_context(sources, bindings)
  end

  defp default_source_context(context) do
    %{
      state: "none",
      data_source_id: context.data_source_id,
      source_binding_id: context.source_binding_id,
      logical_source: context.logical_source_text,
      realm: context.realm,
      matched_data_source_id: nil,
      matched_source_binding_id: nil
    }
  end

  defp resolve_source_context(source_context, sources, bindings) do
    if source_context_requested?(source_context) do
      source_context
      |> Map.put(:state, "pending")
      |> resolve_requested_source_context(sources, bindings)
    else
      source_context
    end
  end

  defp source_context_requested?(source_context) do
    Enum.any?(
      [source_context.data_source_id, source_context.source_binding_id, source_context.realm],
      &present?/1
    )
  end

  defp resolve_requested_source_context(source_context, sources, bindings) do
    sources_by_id = Map.new(sources, &{&1.data_source_id, &1})
    requested_source = requested_source(source_context, sources_by_id)
    requested_binding = requested_binding(source_context, bindings)
    context_binding = context_binding(source_context, bindings)
    matched_binding = first_present(requested_binding, context_binding)

    matched_source =
      first_present(requested_source, binding_source(matched_binding, sources_by_id))

    if source_context_matched?(
         source_context,
         requested_source,
         requested_binding,
         matched_source,
         matched_binding
       ) do
      %{
        source_context
        | state: "matched",
          matched_data_source_id: matched_data_source_id(matched_source),
          matched_source_binding_id: matched_source_binding_id(matched_binding)
      }
    else
      %{source_context | state: "missing"}
    end
  end

  defp requested_source(%{data_source_id: nil}, _sources_by_id), do: nil

  defp requested_source(source_context, sources_by_id),
    do: Map.get(sources_by_id, source_context.data_source_id)

  defp requested_binding(%{source_binding_id: nil}, _bindings), do: nil

  defp requested_binding(source_context, bindings),
    do: find_binding(bindings, source_context.source_binding_id)

  defp context_binding(source_context, bindings),
    do: Enum.find(bindings, &binding_matches_source_context?(&1, source_context))

  defp binding_matches_source_context?(%DataBinding{} = binding, source_context) do
    binding_matches_logical_source?(binding, source_context) and
      binding_matches_realm?(binding, source_context) and
      binding_matches_data_source?(binding, source_context)
  end

  defp binding_matches_logical_source?(%DataBinding{} = binding, source_context),
    do: normalize_string(binding.logical_source) == source_context.logical_source

  defp binding_matches_realm?(_binding, %{realm: nil}), do: true

  defp binding_matches_realm?(%DataBinding{} = binding, source_context),
    do: normalize_string(binding.realm) == source_context.realm

  defp binding_matches_data_source?(_binding, %{data_source_id: nil}), do: true

  defp binding_matches_data_source?(%DataBinding{} = binding, source_context),
    do: binding.data_source_id == source_context.data_source_id

  defp binding_source(nil, _sources_by_id), do: nil

  defp binding_source(%DataBinding{} = binding, sources_by_id),
    do: Map.get(sources_by_id, binding.data_source_id)

  defp source_context_matched?(
         source_context,
         requested_source,
         requested_binding,
         matched_source,
         matched_binding
       ) do
    source_context_requested?(source_context) and
      requested_source_found?(source_context, requested_source) and
      requested_binding_found?(source_context, requested_binding) and
      binding_source_consistent?(source_context, matched_binding) and
      source_context_consistent?(source_context, matched_binding) and
      source_or_binding_found?(matched_source, matched_binding)
  end

  defp requested_source_found?(%{data_source_id: nil}, _requested_source), do: true
  defp requested_source_found?(_source_context, %DataSource{}), do: true
  defp requested_source_found?(_source_context, _requested_source), do: false

  defp requested_binding_found?(%{source_binding_id: nil}, _requested_binding), do: true
  defp requested_binding_found?(_source_context, %DataBinding{}), do: true
  defp requested_binding_found?(_source_context, _requested_binding), do: false

  defp binding_source_consistent?(%{data_source_id: nil}, _binding), do: true
  defp binding_source_consistent?(_source_context, nil), do: true

  defp binding_source_consistent?(source_context, %DataBinding{} = binding),
    do: binding.data_source_id == source_context.data_source_id

  defp source_context_consistent?(source_context, %DataBinding{} = binding),
    do: binding_matches_source_context?(binding, source_context)

  defp source_context_consistent?(%{realm: nil, source_binding_id: nil}, nil), do: true
  defp source_context_consistent?(_source_context, nil), do: false

  defp source_or_binding_found?(nil, nil), do: false
  defp source_or_binding_found?(_source, _binding), do: true

  defp matched_data_source_id(nil), do: nil
  defp matched_data_source_id(%DataSource{} = source), do: source.data_source_id

  defp matched_source_binding_id(nil), do: nil
  defp matched_source_binding_id(%DataBinding{} = binding), do: binding.binding_id

  defp find_binding(bindings, binding_id), do: Enum.find(bindings, &(&1.binding_id == binding_id))

  defp first_present(nil, fallback), do: fallback
  defp first_present(value, _fallback), do: value

  defp load_samples(_organization_id, _mission_id, %{point_id: nil} = context) do
    {[], history_diagnostics([], %{}, context, false)}
  end

  defp load_samples(organization_id, mission_id, context) do
    opts =
      [order: context.order, limit: context.limit]
      |> maybe_put(:spacecraft_id, context.spacecraft_id)
      |> maybe_put(:from_receipt_time, context.from)
      |> maybe_put(:to_receipt_time, context.to)
      |> maybe_put(:selection_view, context.selection_view)
      |> maybe_put(:validity_state, context.validity_state)
      |> maybe_put(:realm, context.realm)
      |> maybe_put(:data_source_id, context.data_source_id)
      |> maybe_put(:binding_id, context.source_binding_id)

    case Cadence.telemetry_history_result(organization_id, mission_id, context.point_id, opts) do
      {:ok, %{samples: samples, diagnostics: diagnostics}} ->
        physical_exists? =
          samples != [] || physical_samples_exist?(organization_id, mission_id, context)

        {samples, history_diagnostics(samples, diagnostics, context, physical_exists?)}

      {:error, reason} ->
        {[], history_diagnostics([], %{error: inspect(reason)}, context, false)}
    end
  end

  defp physical_samples_exist?(organization_id, mission_id, context) do
    opts =
      [
        order: context.order,
        limit: 1,
        selection_view: :all_revisions
      ]
      |> maybe_put(:spacecraft_id, context.spacecraft_id)
      |> maybe_put(:from_receipt_time, context.from)
      |> maybe_put(:to_receipt_time, context.to)
      |> maybe_put(:realm, context.realm)
      |> maybe_put(:data_source_id, context.data_source_id)
      |> maybe_put(:binding_id, context.source_binding_id)

    case Cadence.telemetry_history_result(organization_id, mission_id, context.point_id, opts) do
      {:ok, %{samples: [_ | _]}} -> true
      _other -> false
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp context_rows(context) do
    [
      row("Spacecraft", context.spacecraft_id),
      row("Sample", context.sample_id),
      row("Selected time", context.selected_time),
      row("Mode", context.time_mode),
      row("From", context.from_text),
      row("To", context.to_text),
      row("Order", context.order_text),
      row("Limit", context.limit_text),
      row("Selection", context.selection_view_text),
      row("Validity", context.validity_state_text),
      row("Realm", context.realm),
      row("Logical source", context.logical_source_text),
      row("Data source", context.data_source_id),
      row("Source binding", context.source_binding_id)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp source_context_rows(source_context, samples) do
    [
      row("State", source_context.state),
      row("Requested realm", source_context.realm),
      row("Requested source", source_context.data_source_id),
      row("Requested binding", source_context.source_binding_id),
      row("Matched source", source_context.matched_data_source_id),
      row("Matched binding", source_context.matched_source_binding_id),
      row("Logical source", source_context.logical_source),
      row("Returned sources", returned_source_summary(samples))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp diagnostics_rows(diagnostics) do
    [
      row("Requested", diagnostics.requested_logical_limit),
      row("Returned", diagnostics.logical_selected_count),
      row("Physical", diagnostics.physical_candidate_count),
      row("Candidate cap", diagnostics.physical_candidate_limit),
      row("Effective", diagnostics.effective_selection?),
      row("Exhausted", diagnostics.candidate_window_exhausted?),
      row("Physical exists", diagnostics.physical_samples_exist?),
      row("Error", diagnostics.error)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp history_diagnostics(samples, diagnostics, context, physical_exists?) do
    %{
      requested_logical_limit:
        diagnostics_value(diagnostics, :requested_logical_limit) || context.limit,
      logical_selected_count:
        diagnostics_value(diagnostics, :logical_selected_count) || length(samples),
      physical_candidate_count:
        diagnostics_value(diagnostics, :physical_candidate_count) ||
          physical_count(samples, physical_exists?),
      physical_candidate_limit: diagnostics_value(diagnostics, :physical_candidate_limit),
      effective_selection?:
        diagnostics_value(diagnostics, :effective_selection?) || effective_selection?(context),
      candidate_window_exhausted?:
        diagnostics_value(diagnostics, :candidate_window_exhausted?) || false,
      physical_samples_exist?: physical_exists?,
      selection_view: context.selection_view_text,
      validity_state: context.validity_state_text,
      error: diagnostics_value(diagnostics, :error)
    }
  end

  defp diagnostics_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp diagnostics_value(_map, _key), do: nil

  defp physical_count(samples, true), do: max(length(samples), 1)
  defp physical_count(_samples, false), do: 0

  defp effective_selection?(%{selection_view: :canonical}), do: true
  defp effective_selection?(_context), do: false

  defp empty_samples_message(%{physical_samples_exist?: true}) do
    "Physical samples exist, but none matched the current selection view or validity filter."
  end

  defp empty_samples_message(_diagnostics), do: "No physical samples matched this context."

  defp sample_provenance_rows(sample) do
    [
      row("Sample", sample.sample_id),
      row("Point", sample.point_id),
      row("Spacecraft", sample.spacecraft_id),
      row("Receipt", format_datetime(sample.receipt_time)),
      row("Generation", format_datetime(sample.generation_time)),
      row("Evidence", sample.evidence_id),
      row("Packet", sample.packet_id),
      row("Definition", packet_definition_ref(sample)),
      row("Quality", sample.quality_state),
      row("Validity", validity_state_label(sample)),
      row("Realm", storage_provenance_value(sample, "realm")),
      row("Data source", storage_provenance_value(sample, "data_source_id")),
      row("Source binding", storage_provenance_value(sample, "binding_id")),
      row("Identity", storage_provenance_value(sample, "observation_identity_id")),
      row("Observation", storage_provenance_value(sample, "observation_id")),
      row("Revision", storage_provenance_value(sample, "revision")),
      row("Decision", storage_provenance_value(sample, "decision_reason"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp filter_params(context) do
    %{
      "point_id" => blank(context.point_id),
      "spacecraft_id" => blank(context.spacecraft_id),
      "time_mode" => context.time_mode,
      "from" => blank(context.from_text),
      "to" => blank(context.to_text),
      "order" => context.order_text,
      "limit" => context.limit_text,
      "selection_view" => context.selection_view_text,
      "validity_state" => context.validity_state_text,
      "realm" => blank(context.realm),
      "logical_source" => context.logical_source_text,
      "data_source_id" => blank(context.data_source_id),
      "source_binding_id" => blank(context.source_binding_id),
      "source_dashboard_id" => blank(context.source_dashboard_id),
      "sample_id" => blank(context.sample_id),
      "selected_time" => blank(context.selected_time)
    }
  end

  defp normalize_filter_params(params) do
    time_mode = normalize_time_mode(params["time_mode"])

    params
    |> Map.take(@query_params)
    |> Map.put("time_mode", time_mode)
    |> Map.put("from", if(time_mode == "archive", do: params["from"], else: nil))
    |> Map.put("to", if(time_mode == "archive", do: params["to"], else: nil))
    |> Map.put("order", order_text(params["order"]))
    |> Map.put("limit", limit_text(params["limit"]))
    |> Map.put("selection_view", selection_view_text(params["selection_view"]))
    |> Map.put("validity_state", validity_state_text(params["validity_state"]))
    |> Map.put("logical_source", logical_source_text(params["logical_source"]))
  end

  defp investigation_query(context) do
    %{
      "point_id" => context.point_id,
      "spacecraft_id" => context.spacecraft_id,
      "time_mode" => non_default(context.time_mode, "latest"),
      "from" => if(context.time_mode == "archive", do: context.from_text, else: nil),
      "to" => if(context.time_mode == "archive", do: context.to_text, else: nil),
      "order" => non_default(context.order_text, "desc"),
      "limit" => non_default(context.limit_text, Integer.to_string(@default_limit)),
      "selection_view" => non_default(context.selection_view_text, "canonical"),
      "validity_state" => non_default(context.validity_state_text, ""),
      "realm" => context.realm,
      "logical_source" => non_default(context.logical_source_text, "telemetry"),
      "data_source_id" => context.data_source_id,
      "source_binding_id" => context.source_binding_id,
      "source_dashboard_id" => context.source_dashboard_id,
      "sample_id" => context.sample_id,
      "selected_time" => context.selected_time
    }
    |> compact_query()
  end

  defp incoming_query(params) do
    params
    |> Map.take(@query_params)
    |> compact_query()
  end

  defp non_default(value, value), do: nil
  defp non_default(value, _default), do: value

  defp telemetry_explore_path(mission_id, query) when map_size(query) == 0 do
    ~p"/missions/#{mission_id}/ops/telemetry/explore"
  end

  defp telemetry_explore_path(mission_id, query) do
    ~p"/missions/#{mission_id}/ops/telemetry/explore?#{query}"
  end

  defp investigation_fingerprint(path) do
    :sha256
    |> :crypto.hash(path)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp compact_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp row(_label, nil), do: nil
  defp row(_label, ""), do: nil
  defp row(label, value), do: %{label: label, value: value}

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, _reason} ->
        case DateTime.from_iso8601(value <> "Z") do
          {:ok, datetime, _offset} -> datetime
          {:error, _reason} -> nil
        end
    end
  end

  defp effective_from(%{"time_mode" => "last_5m"}),
    do: DateTime.utc_now() |> DateTime.add(-5 * 60, :second)

  defp effective_from(%{"time_mode" => "last_15m"}),
    do: DateTime.utc_now() |> DateTime.add(-15 * 60, :second)

  defp effective_from(%{"time_mode" => "last_1h"}),
    do: DateTime.utc_now() |> DateTime.add(-60 * 60, :second)

  defp effective_from(%{"time_mode" => "archive", "from" => from}), do: parse_datetime(from)
  defp effective_from(_params), do: nil

  defp effective_to(%{"time_mode" => "archive", "to" => to}), do: parse_datetime(to)
  defp effective_to(_params), do: nil

  defp normalize_time_mode("live"), do: "latest"

  defp normalize_time_mode(value)
       when value in ["latest", "last_5m", "last_15m", "last_1h", "archive"],
       do: value

  defp normalize_time_mode(_value), do: "latest"

  defp parse_order("asc"), do: :asc
  defp parse_order(_value), do: :desc

  defp order_text("asc"), do: "asc"
  defp order_text(_value), do: "desc"

  defp parse_limit(value), do: limit_text(value) |> String.to_integer()

  defp limit_text(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit > 0 -> limit |> min(@max_limit) |> Integer.to_string()
      _invalid -> Integer.to_string(@default_limit)
    end
  end

  defp limit_text(value) when is_integer(value) and value > 0 do
    value |> min(@max_limit) |> Integer.to_string()
  end

  defp limit_text(_value), do: Integer.to_string(@default_limit)

  defp parse_selection_view(value) do
    case selection_view_text(value) do
      "all_revisions" -> :all_revisions
      "as_recorded" -> :as_recorded
      "recomputed" -> :recomputed
      _canonical -> :canonical
    end
  end

  defp selection_view_text(value)
       when value in ["canonical", "all_revisions", "as_recorded", "recomputed"],
       do: value

  defp selection_view_text(_value), do: "canonical"

  defp parse_validity_state(value) do
    case validity_state_text(value) do
      "" -> nil
      "canonical" -> :canonical
      "duplicate" -> :duplicate
      "conflict" -> :conflict
      "superseded" -> :superseded
      "advisory" -> :advisory
    end
  end

  defp validity_state_text(value)
       when value in ["", "canonical", "duplicate", "conflict", "superseded", "advisory"],
       do: value

  defp validity_state_text(_value), do: ""

  defp parse_logical_source(value) do
    case logical_source_text(value) do
      "telemetry" -> :telemetry
      other -> String.to_atom(other)
    end
  end

  defp logical_source_text(value)
       when value in ["telemetry", "limits", "events", "operational_observables"],
       do: value

  defp logical_source_text(_value), do: "telemetry"

  defp text_param(nil), do: nil
  defp text_param(""), do: nil
  defp text_param(value) when is_binary(value), do: value
  defp text_param(value), do: to_string(value)

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp blank(nil), do: ""
  defp blank(value), do: value

  defp dashboard_path(mission_id, dashboard_id) do
    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}"
  end

  defp format_datetime(nil), do: "none"
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp format_value(nil), do: "none"
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format_value(value), do: inspect(value)

  defp packet_definition_ref(sample) do
    case {sample.packet_definition_id, sample.packet_definition_version} do
      {nil, _version} -> "none"
      {definition_id, nil} -> definition_id
      {definition_id, version} -> "#{definition_id}@#{version}"
    end
  end

  defp validity_state_label(sample) do
    case SelectionPolicy.sample_validity_state(sample) do
      nil -> "canonical"
      state -> Atom.to_string(state)
    end
  end

  defp storage_provenance_value(sample, key) do
    sample.provenance
    |> ensure_map()
    |> map_value("storage")
    |> ensure_map()
    |> map_value(key)
    |> format_storage_value()
  end

  defp dashboard_sample_href(_mission_id, %{source_dashboard_id: nil}, _sample), do: nil

  defp dashboard_sample_href(mission_id, context, sample) do
    query =
      %{
        "selected_target" => "telemetry_sample",
        "selected_id" => sample.sample_id,
        "spacecraft_id" => context.spacecraft_id,
        "time_mode" => context.time_mode,
        "from" => context.from_text,
        "to" => context.to_text,
        "realm" => context.realm
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/dashboards/#{context.source_dashboard_id}?#{query}"
  end

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)

  defp format_storage_value(nil), do: nil
  defp format_storage_value(value), do: format_value(value)

  defp sample_source_ref(sample) do
    realm = storage_provenance_value(sample, "realm")
    data_source_id = storage_provenance_value(sample, "data_source_id")
    binding_id = storage_provenance_value(sample, "binding_id")

    [realm, data_source_id, binding_id]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "unattributed"
      parts -> Enum.join(parts, " / ")
    end
  end

  defp returned_source_summary([]), do: nil

  defp returned_source_summary(samples) do
    samples
    |> Enum.map(&sample_source_ref/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {source, _count} -> source end)
    |> Enum.map_join(", ", fn {source, count} -> "#{source} x#{count}" end)
  end

  defp point_options(points, selected_point_id) do
    options = [{"Select a point", ""}] ++ Enum.map(points, &{&1.point_id, &1.point_id})

    if selected_point_id &&
         !Enum.any?(options, fn {_label, value} -> value == selected_point_id end) do
      options ++ [{selected_point_id, selected_point_id}]
    else
      options
    end
  end

  defp spacecraft_options(spacecraft) do
    [{"All spacecraft", ""}] ++
      Enum.map(spacecraft, &{&1.display_name, &1.spacecraft_id})
  end

  defp time_mode_options do
    [
      {"Latest", "latest"},
      {"Last 5 minutes", "last_5m"},
      {"Last 15 minutes", "last_15m"},
      {"Last hour", "last_1h"},
      {"Explicit range", "archive"}
    ]
  end

  defp order_options do
    [
      {"Newest first", "desc"},
      {"Oldest first", "asc"}
    ]
  end

  defp order_label(:asc), do: "oldest first"
  defp order_label(_order), do: "newest first"

  defp realm_options(data_realms, data_bindings, current_realm) do
    realms =
      (data_realms ++ Enum.map(data_bindings, &to_string(&1.realm)) ++ List.wrap(current_realm))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()
      |> Enum.sort()

    [{"Any realm", ""}] ++ Enum.map(realms, &{&1, &1})
  end

  defp logical_source_options do
    [
      {"Telemetry", "telemetry"}
    ]
  end

  defp data_source_options(data_sources, data_bindings, context) do
    allowed_ids =
      data_bindings
      |> Enum.filter(&binding_matches_context?(&1, context))
      |> Enum.map(& &1.data_source_id)
      |> MapSet.new()

    options =
      data_sources
      |> Enum.filter(fn source ->
        MapSet.size(allowed_ids) == 0 or MapSet.member?(allowed_ids, source.data_source_id)
      end)
      |> Enum.map(&{&1.data_source_id, &1.data_source_id})
      |> Enum.sort_by(fn {label, _value} -> label end)

    [{"Any data source", ""}] ++ ensure_option(options, context.data_source_id)
  end

  defp source_binding_options(data_bindings, context) do
    options =
      data_bindings
      |> Enum.filter(&binding_matches_context?(&1, context))
      |> Enum.map(&{binding_option_label(&1), &1.binding_id})
      |> Enum.sort_by(fn {label, _value} -> label end)

    [{"Any binding", ""}] ++ ensure_option(options, context.source_binding_id)
  end

  defp binding_matches_context?(binding, context) do
    normalize_string(binding.logical_source) == context.logical_source_text and
      matches_optional?(normalize_string(binding.realm), context.realm) and
      matches_optional?(binding.data_source_id, context.data_source_id)
  end

  defp matches_optional?(_value, nil), do: true
  defp matches_optional?(_value, ""), do: true
  defp matches_optional?(value, value), do: true
  defp matches_optional?(_value, _expected), do: false

  defp binding_option_label(binding) do
    "#{binding.binding_id} (#{binding.realm} / #{binding.data_source_id})"
  end

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value), do: to_string(value)

  defp ensure_option(options, nil), do: options
  defp ensure_option(options, ""), do: options

  defp ensure_option(options, selected) do
    if Enum.any?(options, fn {_label, value} -> value == selected end) do
      options
    else
      options ++ [{selected, selected}]
    end
  end

  defp selection_view_options do
    [
      {"Canonical", "canonical"},
      {"All revisions", "all_revisions"},
      {"As recorded", "as_recorded"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp validity_state_options do
    [
      {"Any validity", ""},
      {"Canonical", "canonical"},
      {"Duplicate", "duplicate"},
      {"Conflict", "conflict"},
      {"Superseded", "superseded"},
      {"Advisory", "advisory"}
    ]
  end
end
