defmodule CadenceWeb.OpsTelemetryExploreComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Telemetry.SelectionPolicy

  def page(assigns) do
    ~H"""
    <div
      id="ops-telemetry-explore-page"
      class="flex flex-1 min-h-0"
      data-explore-source-state={@source_context.state}
      data-explore-data-source={@source_context.data_source_id || ""}
      data-explore-source-binding={@source_context.source_binding_id || ""}
      data-explore-logical-source={@source_context.logical_source || ""}
      data-explore-realm={@source_context.realm || ""}
      data-explore-selected-sample-state={@selected_sample_state}
      data-explore-selected-sample-id={@explore_context.sample_id || ""}
    >
      <div class="flex-1 min-w-0 overflow-y-auto">
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
      <.mission_context_rail fleet_health={@fleet_health} />
    </div>
    """
  end

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

  defp row(_label, nil), do: nil
  defp row(_label, ""), do: nil
  defp row(label, value), do: %{label: label, value: value}

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

  defp compact_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end
end
