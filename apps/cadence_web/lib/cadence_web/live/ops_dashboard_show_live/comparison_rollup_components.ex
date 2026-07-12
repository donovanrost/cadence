defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ComparisonInvestigationPreset
  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs

  attr :rollup, :map, required: true
  attr :preset, :map, default: nil
  attr :open_review_summary, :map, default: %{}
  attr :saved_presets, :list, default: []

  def comparison_rollup_strip(assigns) do
    assigns =
      assigns
      |> assign(:groups, comparison_rollup_groups(assigns.rollup))
      |> assign(:workflow_groups, comparison_rollup_workflow_groups(assigns.rollup))
      |> assign(
        :review_requested?,
        comparison_rollup_review_requested?(assigns.preset, assigns.open_review_summary)
      )

    ~H"""
    <div
      :if={@rollup.visible? or @saved_presets != []}
      id="dashboard-comparison-rollup"
      data-dashboard-comparison-rollup
      data-dashboard-comparison-widgets={@rollup.widget_count}
      data-dashboard-comparison-deltas={@rollup.delta_count}
      data-dashboard-comparison-unchanged={@rollup.unchanged_count}
      data-dashboard-comparison-coverage={@rollup.coverage_count}
      data-dashboard-comparison-missing={@rollup.missing_count}
      data-dashboard-comparison-handled={comparison_rollup_count(@rollup, :handled_count)}
      data-dashboard-comparison-open={comparison_rollup_count(@rollup, :open_count)}
      data-dashboard-comparison-unhandled={comparison_rollup_count(@rollup, :unhandled_count)}
      data-dashboard-comparison-states={@rollup.states}
      data-dashboard-comparison-delta-placements={comparison_rollup_group_placements(@groups, "deltas")}
      data-dashboard-comparison-missing-placements={comparison_rollup_group_placements(@groups, "missing")}
      data-dashboard-comparison-coverage-placements={comparison_rollup_group_placements(@groups, "coverage")}
      data-dashboard-comparison-unchanged-placements={comparison_rollup_group_placements(@groups, "unchanged")}
      data-dashboard-comparison-open-placements={comparison_rollup_group_placements(@workflow_groups, "open")}
      data-dashboard-comparison-handled-placements={comparison_rollup_group_placements(@workflow_groups, "handled")}
      data-dashboard-comparison-preset={comparison_rollup_preset_json(@preset)}
      data-dashboard-comparison-preset-path={comparison_rollup_preset_path(@preset)}
      data-dashboard-comparison-open-findings={comparison_rollup_open_findings_json(@preset)}
      data-dashboard-comparison-open-findings-review-state={comparison_rollup_review_state(@review_requested?)}
      data-dashboard-comparison-open-findings-review-request-ids={comparison_rollup_open_review_request_ids(@open_review_summary)}
      data-dashboard-comparison-saved-presets={length(@saved_presets)}
      class="shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-info/30 bg-info/10 text-xs"
    >
      <span class="hud-label">Compare</span>
      <span class="text-base-content/70">
        {@rollup.widget_count} widgets
      </span>
      <span
        :if={comparison_rollup_count(@rollup, :open_count) > 0}
        class="badge badge-warning badge-xs"
        data-dashboard-comparison-workflow-badge="open"
        data-dashboard-comparison-rollup-placements={comparison_rollup_group_placements(@workflow_groups, "open")}
      >
        {comparison_rollup_count(@rollup, :open_count)} open
      </span>
      <span
        :if={comparison_rollup_count(@rollup, :handled_count) > 0}
        class="badge badge-success badge-outline badge-xs"
        data-dashboard-comparison-workflow-badge="handled"
        data-dashboard-comparison-rollup-placements={comparison_rollup_group_placements(@workflow_groups, "handled")}
      >
        {comparison_rollup_count(@rollup, :handled_count)} handled
      </span>
      <span
        :if={@rollup.delta_count > 0}
        class="badge badge-info badge-xs"
        data-dashboard-comparison-rollup-badge="deltas"
        data-dashboard-comparison-rollup-placements={comparison_rollup_group_placements(@groups, "deltas")}
      >
        {@rollup.delta_count} deltas
      </span>
      <span
        :if={@rollup.unchanged_count > 0}
        class="badge badge-success badge-outline badge-xs"
        data-dashboard-comparison-rollup-badge="unchanged"
        data-dashboard-comparison-rollup-placements={comparison_rollup_group_placements(@groups, "unchanged")}
      >
        {@rollup.unchanged_count} unchanged
      </span>
      <span
        :if={@rollup.coverage_count > 0}
        class="badge badge-info badge-outline badge-xs"
        data-dashboard-comparison-rollup-badge="coverage"
        data-dashboard-comparison-rollup-placements={comparison_rollup_group_placements(@groups, "coverage")}
      >
        {@rollup.coverage_count} coverage
      </span>
      <span
        :if={@rollup.missing_count > 0}
        class="badge badge-warning badge-outline badge-xs"
        data-dashboard-comparison-rollup-badge="missing"
        data-dashboard-comparison-rollup-placements={comparison_rollup_group_placements(@groups, "missing")}
      >
        {@rollup.missing_count} missing
      </span>
      <button
        :if={comparison_rollup_open_findings_json(@preset)}
        id="dashboard-comparison-open-findings-copy"
        type="button"
        phx-hook="ClipboardButton"
        data-clipboard-text={comparison_rollup_open_findings_json(@preset)}
        data-dashboard-comparison-open-findings-copy
        class="btn btn-ghost btn-xs gap-1"
        title="Copy open comparison findings"
      >
        <.icon name="hero-clipboard-document-list" class="h-3.5 w-3.5" /> Open
      </button>
      <form
        :if={comparison_rollup_open_findings_json(@preset)}
        id="dashboard-comparison-open-findings-review-form"
        phx-submit="request_comparison_review"
        class="inline-flex items-center"
      >
        <input
          id="dashboard-comparison-open-findings-review-payload"
          type="hidden"
          name="review[open_findings]"
          value={comparison_rollup_open_findings_json(@preset)}
        />
        <button
          id="dashboard-comparison-open-findings-review"
          type="submit"
          class="btn btn-ghost btn-xs gap-1"
          title={comparison_rollup_review_title(@review_requested?)}
          disabled={@review_requested?}
          data-dashboard-comparison-open-findings-review
          data-dashboard-comparison-open-findings-review-state={comparison_rollup_review_state(@review_requested?)}
        >
          <.icon name="hero-flag" class="h-3.5 w-3.5" /> Review
        </button>
      </form>
      <button
        :if={comparison_rollup_preset_path(@preset)}
        id="dashboard-comparison-preset-copy"
        type="button"
        phx-hook="ClipboardButton"
        data-clipboard-text={comparison_rollup_preset_path(@preset)}
        data-dashboard-comparison-preset-copy
        class="btn btn-ghost btn-xs gap-1"
        title="Copy comparison investigation preset link"
      >
        <.icon name="hero-bookmark-square" class="h-3.5 w-3.5" /> Preset
      </button>
      <form
        :if={@preset}
        id="dashboard-comparison-preset-form"
        phx-submit="save_comparison_preset"
        class="join items-center"
      >
        <.input
          id="dashboard-comparison-preset-name"
          name="preset[name]"
          type="text"
          value=""
          placeholder="Preset name"
          maxlength="120"
          compact
          class="input-xs join-item w-40"
        />
        <button
          id="dashboard-comparison-preset-save"
          type="submit"
          class="btn btn-xs btn-outline join-item gap-1"
          title="Save comparison investigation preset"
        >
          <.icon name="hero-bookmark" class="h-3.5 w-3.5" /> Save
        </button>
      </form>
      <details
        :if={@saved_presets != []}
        id="dashboard-comparison-saved-presets"
        class="dropdown dropdown-end"
        data-dashboard-comparison-saved-presets={length(@saved_presets)}
      >
        <summary class="btn btn-ghost btn-xs gap-1">
          <.icon name="hero-book-open" class="h-3.5 w-3.5" />
          Saved
          <span class="badge badge-xs">{length(@saved_presets)}</span>
        </summary>
        <div class="dropdown-content z-[var(--z-popover)] mt-1 w-96 rounded border border-base-300 bg-base-100 p-2 text-xs shadow-lg">
          <div
            :for={preset <- @saved_presets}
            class="border-b border-base-300/60 py-2 last:border-b-0"
            data-dashboard-comparison-saved-preset={saved_preset_id(preset)}
            data-dashboard-comparison-saved-preset-name={saved_preset_name(preset)}
            data-dashboard-comparison-saved-preset-primary-view={saved_preset_primary_view(preset)}
            data-dashboard-comparison-saved-preset-compare-view={saved_preset_compare_view(preset)}
            data-dashboard-comparison-saved-preset-affected={saved_preset_affected_count(preset)}
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <div class="truncate font-semibold text-base-content">
                  {saved_preset_name(preset)}
                </div>
                <div class="mt-0.5 font-mono text-[0.68rem] text-base-content/60">
                  {saved_preset_view_pair(preset)} - {saved_preset_affected_count(preset)} affected
                </div>
              </div>
              <div class="join shrink-0">
                <button
                  type="button"
                  class="btn btn-xs btn-ghost join-item"
                  phx-click="apply_comparison_preset"
                  phx-value-preset-id={saved_preset_id(preset)}
                  title="Load comparison preset"
                  data-dashboard-comparison-saved-preset-apply={saved_preset_id(preset)}
                >
                  <.icon name="hero-arrow-path" class="h-3.5 w-3.5" /> Load
                </button>
                <button
                  type="button"
                  class="btn btn-xs btn-ghost join-item text-error"
                  phx-click="delete_comparison_preset"
                  phx-value-preset-id={saved_preset_id(preset)}
                  data-confirm="Delete this comparison preset?"
                  title="Delete comparison preset"
                  data-dashboard-comparison-saved-preset-delete={saved_preset_id(preset)}
                >
                  <.icon name="hero-trash" class="h-3.5 w-3.5" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </details>
      <details
        :if={@groups != []}
        id="dashboard-comparison-rollup-detail"
        class="dropdown dropdown-end"
        data-dashboard-comparison-rollup-detail
      >
        <summary class="btn btn-ghost btn-xs gap-1">
          <.icon name="hero-list-bullet" class="h-3.5 w-3.5" /> Details
        </summary>
        <div class="dropdown-content z-[var(--z-popover)] mt-1 w-96 rounded border border-base-300 bg-base-100 p-2 text-xs shadow-lg">
          <div
            :for={group <- @workflow_groups}
            class="border-b border-base-300/60 py-2 last:border-b-0"
            data-dashboard-comparison-rollup-workflow-group={group.key}
            data-dashboard-comparison-rollup-workflow-group-count={group.count}
            data-dashboard-comparison-rollup-placements={group.placement_ids}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="hud-label">{group.label}</span>
              <span class="font-mono text-base-content/60">{group.count}</span>
            </div>
            <ul class="mt-1 space-y-1">
              <li
                :for={item <- group.items}
                data-dashboard-comparison-rollup-workflow-item={item.placement_id}
                data-dashboard-comparison-rollup-workflow-state={item.state}
                data-dashboard-comparison-rollup-workflow-decision-status={comparison_rollup_item_value(item, :decision_status)}
                class="flex items-center justify-between gap-2 rounded px-1 py-0.5 hover:bg-base-200"
              >
                <a href={comparison_rollup_item_href(item)} class="min-w-0 flex-1 truncate">
                  {item.title}
                </a>
                <span
                  :if={comparison_rollup_item_value(item, :decision_status) == "applied"}
                  class="badge badge-success badge-outline badge-xs"
                >
                  Handled
                </span>
                <span class="font-mono text-base-content/60">{item.label}</span>
              </li>
            </ul>
          </div>
          <div
            :for={group <- @groups}
            class="border-b border-base-300/60 py-2 last:border-b-0"
            data-dashboard-comparison-rollup-group={group.key}
            data-dashboard-comparison-rollup-group-count={group.count}
            data-dashboard-comparison-rollup-group-handled={comparison_rollup_count(group, :handled_count)}
            data-dashboard-comparison-rollup-group-unhandled={comparison_rollup_count(group, :unhandled_count)}
            data-dashboard-comparison-rollup-placements={group.placement_ids}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="hud-label">{group.label}</span>
              <span class="font-mono text-base-content/60">{group.count}</span>
            </div>
            <ul class="mt-1 space-y-1">
              <li
                :for={item <- group.items}
                data-dashboard-comparison-rollup-item={item.placement_id}
                data-dashboard-comparison-rollup-item-state={item.state}
                data-dashboard-comparison-rollup-item-widget={item.widget_id}
                data-dashboard-comparison-rollup-widget-type={comparison_rollup_item_value(item, :widget_type)}
                data-dashboard-comparison-rollup-widget-source={comparison_rollup_item_value(item, :widget_source)}
                data-dashboard-comparison-rollup-primary-kind={comparison_rollup_item_value(item, :primary_kind)}
                data-dashboard-comparison-rollup-compare-kind={comparison_rollup_item_value(item, :compare_kind)}
                data-dashboard-comparison-rollup-primary-observables={comparison_rollup_item_list_text(item, :primary_observable_ids)}
                data-dashboard-comparison-rollup-compare-observables={comparison_rollup_item_list_text(item, :compare_observable_ids)}
                data-dashboard-comparison-rollup-primary-count={comparison_rollup_item_value(item, :primary_count)}
                data-dashboard-comparison-rollup-compare-count={comparison_rollup_item_value(item, :compare_count)}
                data-dashboard-comparison-rollup-delta={comparison_rollup_item_value(item, :delta)}
                data-dashboard-comparison-rollup-primary-sample={comparison_rollup_item_value(item, :primary_sample_id)}
                data-dashboard-comparison-rollup-compare-sample={comparison_rollup_item_value(item, :compare_sample_id)}
                data-dashboard-comparison-rollup-decision-status={comparison_rollup_item_value(item, :decision_status)}
                data-dashboard-comparison-rollup-decision-event={comparison_rollup_item_value(item, :decision_event_id)}
                data-dashboard-comparison-rollup-decision={comparison_rollup_item_value(item, :decision)}
                data-dashboard-comparison-rollup-decision-reason={comparison_rollup_item_value(item, :decision_reason)}
                data-dashboard-comparison-rollup-primary-data-management={comparison_rollup_item_data_management_codes(item, :primary_data_management)}
                data-dashboard-comparison-rollup-compare-data-management={comparison_rollup_item_data_management_codes(item, :compare_data_management)}
                data-dashboard-comparison-rollup-primary-link={item |> comparison_rollup_item_link(:primary_data_link) |> comparison_rollup_link_id()}
                data-dashboard-comparison-rollup-compare-link={item |> comparison_rollup_item_link(:compare_data_link) |> comparison_rollup_link_id()}
                data-dashboard-comparison-rollup-primary-link-target={item |> comparison_rollup_item_link(:primary_data_link) |> comparison_rollup_link_target()}
                data-dashboard-comparison-rollup-compare-link-target={item |> comparison_rollup_item_link(:compare_data_link) |> comparison_rollup_link_target()}
                data-dashboard-comparison-rollup-scope-kind={comparison_rollup_item_value(item, :scope_kind)}
                data-dashboard-comparison-rollup-scope-id={comparison_rollup_item_value(item, :scope_id)}
                data-dashboard-comparison-rollup-scope-ids={comparison_rollup_item_list_text(item, :scope_ids)}
                data-dashboard-comparison-rollup-resource-id={comparison_rollup_item_value(item, :resource_id)}
                data-dashboard-comparison-rollup-spacecraft-id={comparison_rollup_item_value(item, :spacecraft_id)}
                data-dashboard-comparison-rollup-contact-id={comparison_rollup_item_value(item, :contact_id)}
                data-dashboard-comparison-rollup-contact-ids={comparison_rollup_item_list_text(item, :contact_ids)}
                data-dashboard-comparison-rollup-transport-id={comparison_rollup_item_value(item, :transport_id)}
                data-dashboard-comparison-rollup-source-endpoint-id={comparison_rollup_item_value(item, :source_endpoint_id)}
                data-dashboard-comparison-rollup-ground-station-id={comparison_rollup_item_value(item, :ground_station_id)}
                data-dashboard-comparison-rollup-scope-link-id={comparison_rollup_item_value(item, :scope_link_id)}
              >
                <div class="flex items-center justify-between gap-2 rounded px-1 py-0.5 hover:bg-base-200">
                  <a href={comparison_rollup_item_href(item)} class="min-w-0 flex-1 truncate">
                    {item.title}
                  </a>
                  <span
                    :if={comparison_rollup_item_value(item, :decision_status) == "applied"}
                    class="badge badge-success badge-outline badge-xs"
                    title="Comparison finding has an applied revision decision"
                    data-dashboard-comparison-rollup-handled={item.placement_id}
                  >
                    Handled
                  </span>
                  <span class="font-mono text-base-content/60">{item.label}</span>
                  <button
                    :if={comparison_rollup_item_value(item, :decision_event_id)}
                    type="button"
                    phx-click="open_data_link"
                    {DataLinkAttrs.open(comparison_rollup_handoff_link(item),
                      link_id:
                        "comparison-decision:#{comparison_rollup_item_value(item, :decision_event_id)}",
                      target: "telemetry_revision_decision_event",
                      target_id: comparison_rollup_item_value(item, :decision_event_id),
                      scope_kind: comparison_rollup_item_value(item, :scope_kind),
                      scope_id: comparison_rollup_item_value(item, :scope_id),
                      scope_ids: comparison_rollup_item_list_text(item, :scope_ids),
                      resource_id: comparison_rollup_item_value(item, :resource_id),
                      spacecraft_id: comparison_rollup_item_value(item, :spacecraft_id),
                      contact_id: comparison_rollup_item_value(item, :contact_id),
                      contact_ids: comparison_rollup_item_list_text(item, :contact_ids),
                      transport_id: comparison_rollup_item_value(item, :transport_id),
                      source_endpoint_id:
                        comparison_rollup_item_value(item, :source_endpoint_id),
                      ground_station_id:
                        comparison_rollup_item_value(item, :ground_station_id),
                      scope_link_id: comparison_rollup_item_value(item, :scope_link_id),
                      data_view: comparison_rollup_item_value(item, :primary_view)
                    )}
                    class="btn btn-ghost btn-xs btn-square"
                    title="Inspect applied decision"
                    aria-label="Inspect applied decision"
                    data-dashboard-comparison-rollup-decision-link={item.placement_id}
                  >
                    <.icon name="hero-clipboard-document-check" class="h-3.5 w-3.5" />
                  </button>
                  <button
                    :if={comparison_rollup_handoff?(item)}
                    type="button"
                    phx-click="open_data_link"
                    {DataLinkAttrs.open(comparison_rollup_handoff_link(item),
                      link_id: comparison_rollup_handoff_link_id(item),
                      target: "comparison_finding",
                      target_id: item.placement_id,
                      placement_id: item.placement_id,
                      widget_id: item.widget_id,
                      widget_title: item.title,
                      widget_type: comparison_rollup_item_value(item, :widget_type),
                      widget_source: comparison_rollup_item_value(item, :widget_source),
                      primary_kind: comparison_rollup_item_value(item, :primary_kind),
                      compare_kind: comparison_rollup_item_value(item, :compare_kind),
                      primary_observables:
                        comparison_rollup_item_list_text(item, :primary_observable_ids),
                      compare_observables:
                        comparison_rollup_item_list_text(item, :compare_observable_ids),
                      comparison_state: item.state,
                      comparison_delta: comparison_rollup_item_value(item, :delta),
                      primary_count: comparison_rollup_item_value(item, :primary_count),
                      compare_count: comparison_rollup_item_value(item, :compare_count),
                      primary_sample_id: comparison_rollup_item_value(item, :primary_sample_id),
                      compare_sample_id: comparison_rollup_item_value(item, :compare_sample_id),
                      primary_data_view: comparison_rollup_item_value(item, :primary_view),
                      compare_data_view: comparison_rollup_item_value(item, :compare_view),
                      primary_data_management:
                        comparison_rollup_item_data_management_codes(
                          item,
                          :primary_data_management
                        ),
                      compare_data_management:
                        comparison_rollup_item_data_management_codes(
                          item,
                          :compare_data_management
                        ),
                      scope_kind: comparison_rollup_item_value(item, :scope_kind),
                      scope_id: comparison_rollup_item_value(item, :scope_id),
                      scope_ids: comparison_rollup_item_list_text(item, :scope_ids),
                      resource_id: comparison_rollup_item_value(item, :resource_id),
                      spacecraft_id: comparison_rollup_item_value(item, :spacecraft_id),
                      contact_id: comparison_rollup_item_value(item, :contact_id),
                      contact_ids: comparison_rollup_item_list_text(item, :contact_ids),
                      transport_id: comparison_rollup_item_value(item, :transport_id),
                      source_endpoint_id:
                        comparison_rollup_item_value(item, :source_endpoint_id),
                      ground_station_id:
                        comparison_rollup_item_value(item, :ground_station_id),
                      scope_link_id: comparison_rollup_item_value(item, :scope_link_id),
                      data_view: comparison_rollup_item_value(item, :primary_view)
                    )}
                    class="btn btn-ghost btn-xs btn-square"
                    title="Open comparison finding"
                    aria-label="Open comparison finding"
                    data-dashboard-comparison-rollup-handoff={item.placement_id}
                  >
                    <.icon name="hero-arrow-turn-down-right" class="h-3.5 w-3.5" />
                  </button>
                  <button
                    :if={item |> comparison_rollup_item_link(:primary_data_link) |> comparison_rollup_link_id()}
                    type="button"
                    phx-click="open_data_link"
                    {DataLinkAttrs.open(comparison_rollup_item_link(item, :primary_data_link),
                      placement_id: item.placement_id
                    )}
                    class="btn btn-ghost btn-xs btn-square"
                    title="Inspect primary data"
                    aria-label="Inspect primary data"
                    data-dashboard-comparison-rollup-link="primary"
                  >
                    <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" />
                  </button>
                  <button
                    :if={item |> comparison_rollup_item_link(:compare_data_link) |> comparison_rollup_link_id()}
                    type="button"
                    phx-click="open_data_link"
                    {DataLinkAttrs.open(comparison_rollup_item_link(item, :compare_data_link),
                      placement_id: item.placement_id
                    )}
                    class="btn btn-ghost btn-xs btn-square"
                    title="Inspect compare data"
                    aria-label="Inspect compare data"
                    data-dashboard-comparison-rollup-link="compare"
                  >
                    <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" />
                  </button>
                </div>
              </li>
            </ul>
          </div>
        </div>
      </details>
    </div>
    """
  end

  defp comparison_rollup_groups(rollup) when is_map(rollup), do: Map.get(rollup, :groups, [])
  defp comparison_rollup_groups(_rollup), do: []

  defp comparison_rollup_workflow_groups(rollup) when is_map(rollup),
    do: Map.get(rollup, :workflow_groups, [])

  defp comparison_rollup_workflow_groups(_rollup), do: []

  defp comparison_rollup_group_placements(groups, key) do
    groups
    |> Enum.find_value("", fn group ->
      if Map.get(group, :key) == key, do: Map.get(group, :placement_ids, "")
    end)
  end

  defp comparison_rollup_count(item, key) when is_map(item), do: Map.get(item, key, 0)
  defp comparison_rollup_count(_item, _key), do: 0

  defp comparison_rollup_item_href(%{placement_id: placement_id})
       when is_binary(placement_id) and placement_id != "",
       do: "#widget-#{placement_id}"

  defp comparison_rollup_item_href(_item), do: "#"

  defp comparison_rollup_preset_json(preset),
    do: ComparisonInvestigationPreset.encode(preset)

  defp comparison_rollup_open_findings_json(preset),
    do: ComparisonInvestigationPreset.encode_open_findings(preset)

  defp comparison_rollup_review_requested?(preset, open_review_summary) do
    preset_placement_ids =
      preset
      |> ComparisonInvestigationPreset.open_findings_export()
      |> open_findings_placement_ids()

    open_placement_ids =
      open_review_summary
      |> Map.get(:placement_ids, [])
      |> placement_ids()

    preset_placement_ids != [] and Enum.any?(preset_placement_ids, &(&1 in open_placement_ids))
  end

  defp comparison_rollup_review_state(true), do: "requested"
  defp comparison_rollup_review_state(false), do: "available"

  defp comparison_rollup_review_title(true), do: "Comparison review already requested"
  defp comparison_rollup_review_title(false), do: "Request review for open comparison findings"

  defp comparison_rollup_open_review_request_ids(open_review_summary)
       when is_map(open_review_summary) do
    open_review_summary
    |> Map.get(:request_ids, [])
    |> placement_ids()
    |> Enum.join(",")
  end

  defp comparison_rollup_open_review_request_ids(_open_review_summary), do: ""

  defp open_findings_placement_ids(%{} = open_findings) do
    placement_ids =
      open_findings
      |> get_in(["comparison", "open_placement_ids"])
      |> placement_ids()

    if placement_ids == [] do
      open_findings
      |> Map.get("findings")
      |> case do
        findings when is_list(findings) ->
          findings
          |> Enum.map(&Map.get(&1, "placement_id"))
          |> placement_ids()

        _value ->
          []
      end
    else
      placement_ids
    end
  end

  defp open_findings_placement_ids(_open_findings), do: []

  defp placement_ids(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(_values), do: []

  defp comparison_rollup_preset_path(preset),
    do: ComparisonInvestigationPreset.path(preset)

  defp comparison_rollup_handoff?(item) when is_map(item) do
    Map.get(item, :state) in ["increased", "decreased", "missing", "available"] and
      present_text(Map.get(item, :placement_id))
  end

  defp comparison_rollup_handoff?(_item), do: false

  defp comparison_rollup_handoff_link_id(item) when is_map(item),
    do: "comparison:#{Map.get(item, :placement_id)}"

  defp comparison_rollup_handoff_link(item) do
    if is_map(item) do
      comparison_rollup_item_link(item, :primary_data_link) ||
        comparison_rollup_item_link(item, :compare_data_link)
    end
  end

  defp saved_preset_id(preset), do: map_value(preset, :dashboard_investigation_preset_id, "")

  defp saved_preset_name(preset), do: map_value(preset, :name, "Untitled preset")

  defp saved_preset_primary_view(preset), do: map_value(preset, :primary_data_view, "canonical")

  defp saved_preset_compare_view(preset), do: map_value(preset, :compare_data_view, "compare")

  defp saved_preset_affected_count(preset) do
    preset
    |> map_value(:affected_placement_ids, [])
    |> case do
      values when is_list(values) -> length(values)
      _value -> 0
    end
  end

  defp saved_preset_view_pair(preset) do
    "#{data_view_label(saved_preset_primary_view(preset))} vs #{data_view_label(saved_preset_compare_view(preset))}"
  end

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default

  defp comparison_rollup_item_value(item, key) when is_map(item), do: Map.get(item, key)
  defp comparison_rollup_item_value(_item, _key), do: nil

  defp comparison_rollup_item_list_text(item, key) when is_map(item) do
    item
    |> Map.get(key)
    |> list_text()
  end

  defp comparison_rollup_item_list_text(_item, _key), do: nil

  defp comparison_rollup_item_data_management_codes(item, key) when is_map(item) do
    item
    |> Map.get(key)
    |> data_management_codes()
  end

  defp comparison_rollup_item_data_management_codes(_item, _key), do: nil

  defp data_management_codes(%{badges: badges}) when is_list(badges) do
    badges
    |> Enum.map(&data_management_badge_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
    |> present_text()
  end

  defp data_management_codes(%{"badges" => badges}) when is_list(badges) do
    data_management_codes(%{badges: badges})
  end

  defp data_management_codes(_summary), do: nil

  defp data_management_badge_value(%{value: value}), do: present_text(value)
  defp data_management_badge_value(%{"value" => value}), do: present_text(value)
  defp data_management_badge_value(_badge), do: nil

  defp list_text(values) when is_list(values) do
    values
    |> Enum.map(&present_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
    |> present_text()
  end

  defp list_text(value), do: present_text(value)

  defp comparison_rollup_item_link(item, key) when is_map(item), do: Map.get(item, key)
  defp comparison_rollup_item_link(_item, _key), do: nil

  defp comparison_rollup_link_id(link) when is_map(link),
    do: Map.get(link, :link_id, Map.get(link, "link_id"))

  defp comparison_rollup_link_id(_link), do: nil

  defp comparison_rollup_link_target(link) when is_map(link) do
    Map.get(link, :target_text, Map.get(link, "target_text")) ||
      Map.get(link, :target, Map.get(link, "target"))
  end

  defp comparison_rollup_link_target(_link), do: nil

  defp data_view_options do
    [
      {"Canonical", "canonical"},
      {"As recorded", "as_recorded"},
      {"All revisions", "all_revisions"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp data_view_label(value) do
    value = present_text(value)

    data_view_options()
    |> Enum.find_value(value || "Canonical", fn {label, option_value} ->
      if option_value == value, do: label
    end)
  end

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil
end
