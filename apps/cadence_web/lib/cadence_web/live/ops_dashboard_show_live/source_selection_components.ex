defmodule CadenceWeb.OpsDashboardShowLive.SourceSelectionComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :selections, :list, required: true
  attr :mission_id, :string, default: nil

  def source_selection_strip(assigns) do
    ~H"""
    <div
      :if={@selections != []}
      id="dashboard-source-selection"
      data-source-selection-requests={length(@selections)}
      data-source-selection-request-ids={source_selection_request_ids(@selections)}
      data-source-selection-bindings={source_selection_bindings(@selections)}
      data-source-selection-data-sources={source_selection_data_sources(@selections)}
      data-source-selection-rejected={source_selection_rejected_count(@selections)}
      class="shrink-0 flex items-center gap-2 px-2 py-1 border-b border-base-300/60 bg-base-200/30 text-xs"
    >
      <span class="hud-label">Source selection</span>
      <.source_selection_badge
        :for={selection <- @selections}
        selection={selection}
        mission_id={@mission_id}
      />
    </div>
    """
  end

  attr :selection, :map, required: true
  attr :mission_id, :string, default: nil

  defp source_selection_badge(assigns) do
    ~H"""
    <details class="dropdown dropdown-end" data-source-selection-detail={@selection.request_id}>
      <summary
        class={[
          "badge badge-xs cursor-pointer gap-1",
          source_selection_badge_class(@selection)
        ]}
        data-source-selection={@selection.request_id}
        data-source-selection-state={@selection.state_text}
        data-source-selection-logical-source={source_selection_text(@selection, :logical_source_text)}
        data-source-selection-binding={source_selection_text(@selection, :selected_binding_id)}
        data-source-selection-data-source={source_selection_text(@selection, :selected_data_source_id)}
        data-source-selection-candidates={source_selection_text(@selection, :candidate_count)}
        data-source-selection-eligible={source_selection_text(@selection, :eligible_candidate_count)}
        data-source-selection-rejected={source_selection_text(@selection, :rejected_candidate_count)}
        title={source_selection_title(@selection)}
      >
        <.icon name="hero-adjustments-horizontal" class="h-3 w-3" />
        <span>{@selection.logical_source_text}</span>
      </summary>
      <div class="dropdown-content z-[var(--z-popover)] mt-1 w-[34rem] rounded border border-base-300 bg-base-100 p-2 text-xs shadow-lg">
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0">
            <div class="font-semibold text-base-content">
              {@selection.logical_source_text} source selection
            </div>
            <div class="mt-0.5 font-mono text-[0.68rem] text-base-content/60">
              {@selection.request_id}
            </div>
          </div>
          <span class={["badge badge-xs", source_selection_badge_class(@selection)]}>
            {@selection.state_text}
          </span>
        </div>
        <dl class="mt-2 grid grid-cols-[8rem_minmax(0,1fr)] gap-x-2 gap-y-1">
          <dt class="text-base-content/60">Strategy</dt>
          <dd class="font-mono text-base-content">{@selection.strategy_text}</dd>
          <dt class="text-base-content/60">Selected binding</dt>
          <dd class="font-mono text-base-content break-all">
            {source_selection_text(@selection, :selected_binding_id)}
          </dd>
          <dt class="text-base-content/60">Selected source</dt>
          <dd class="font-mono text-base-content break-all">
            {source_selection_text(@selection, :selected_data_source_id)}
          </dd>
          <dt :if={@selection.selected_dataset} class="text-base-content/60">Dataset</dt>
          <dd :if={@selection.selected_dataset} class="font-mono text-base-content break-all">
            {@selection.selected_dataset}
          </dd>
          <dt :if={@selection.requested_realm} class="text-base-content/60">Requested realm</dt>
          <dd :if={@selection.requested_realm} class="font-mono text-base-content">
            {@selection.requested_realm}
          </dd>
          <dt class="text-base-content/60">Candidates</dt>
          <dd class="font-mono text-base-content">
            {@selection.eligible_candidate_count}/{@selection.candidate_count} eligible
          </dd>
        </dl>
        <div
          :if={@selection.candidates != []}
          class="mt-2 overflow-hidden rounded border border-base-300/70"
        >
          <div
            :for={candidate <- @selection.candidates}
            class="grid grid-cols-[minmax(0,1.1fr)_minmax(0,1.1fr)_5rem_minmax(0,0.9fr)_minmax(0,1.2fr)_auto] gap-2 border-b border-base-300/60 px-2 py-1 last:border-b-0"
            data-source-selection-candidate={candidate.binding_id || ""}
            data-source-selection-candidate-source={candidate.data_source_id || ""}
            data-source-selection-candidate-decision={candidate.decision_text || ""}
            data-source-selection-candidate-reasons={candidate.reasons_text || ""}
            data-source-selection-candidate-window={source_selection_candidate_window(candidate)}
            data-source-selection-candidate-health={candidate.source_health_text || ""}
            data-source-selection-candidate-freshness={candidate.source_health_freshness_text || ""}
            data-source-selection-candidate-requested-products={
              Map.get(candidate, :requested_products_text, "")
            }
            data-source-selection-candidate-supported-products={
              Map.get(candidate, :supported_products_text, "")
            }
            data-source-selection-candidate-missing-products={
              Map.get(candidate, :missing_products_text, "")
            }
            data-source-selection-candidate-action={source_selection_candidate_action(candidate)}
            data-source-selection-candidate-action-query={source_selection_candidate_query(candidate)}
          >
            <span class="min-w-0 truncate font-mono text-base-content">
              {candidate.binding_id}
            </span>
            <span class="min-w-0 truncate font-mono text-base-content/70">
              {candidate.data_source_id}
            </span>
            <span class={["badge badge-xs", source_selection_candidate_class(candidate)]}>
              {candidate.decision_text}
            </span>
            <span class="min-w-0 truncate font-mono text-base-content/60">
              {source_selection_candidate_reason(candidate)}
            </span>
            <span class="min-w-0 truncate font-mono text-base-content/60">
              {source_selection_candidate_window(candidate)}
            </span>
            <.link
              :if={source_selection_candidate_href(@mission_id, candidate)}
              navigate={source_selection_candidate_href(@mission_id, candidate)}
              class="btn btn-ghost btn-xs gap-1"
              data-source-selection-candidate-open={
                candidate.binding_id || candidate.data_source_id || ""
              }
              title={candidate.inventory_action_label || "Open source inventory"}
            >
              <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
              Open
            </.link>
            <span
              :if={source_selection_candidate_products(candidate) != ""}
              class="col-span-full min-w-0 truncate font-mono text-[0.68rem] text-warning"
              data-source-selection-candidate-product-summary={
                candidate.binding_id || candidate.data_source_id || ""
              }
            >
              {source_selection_candidate_products(candidate)}
            </span>
          </div>
        </div>
      </div>
    </details>
    """
  end

  defp source_selection_request_ids(selections) do
    selections
    |> Enum.map(&source_selection_text(&1, :request_id))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
  end

  defp source_selection_bindings(selections) do
    selections
    |> Enum.map(&source_selection_text(&1, :selected_binding_id))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
  end

  defp source_selection_data_sources(selections) do
    selections
    |> Enum.map(&source_selection_text(&1, :selected_data_source_id))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
  end

  defp source_selection_rejected_count(selections) do
    selections
    |> Enum.map(&Map.get(&1, :rejected_candidate_count, 0))
    |> Enum.sum()
  end

  defp source_selection_title(selection) do
    [
      source_selection_text(selection, :logical_source_text),
      source_selection_title_part(
        "binding",
        source_selection_text(selection, :selected_binding_id)
      ),
      source_selection_title_part(
        "source",
        source_selection_text(selection, :selected_data_source_id)
      ),
      source_selection_title_part("state", source_selection_text(selection, :state_text)),
      source_selection_title_part(
        "candidates",
        "#{source_selection_text(selection, :eligible_candidate_count)}/#{source_selection_text(selection, :candidate_count)} eligible"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp source_selection_title_part(_label, ""), do: nil
  defp source_selection_title_part(label, value), do: "#{label}: #{value}"

  defp source_selection_text(selection, key) when is_map(selection) do
    selection
    |> Map.get(key)
    |> source_selection_value_text()
  end

  defp source_selection_text(_selection, _key), do: ""

  defp source_selection_value_text(nil), do: ""
  defp source_selection_value_text(value) when is_binary(value), do: value
  defp source_selection_value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp source_selection_value_text(value), do: to_string(value)

  defp source_selection_badge_class(%{state: :selected}), do: "badge-success badge-outline"
  defp source_selection_badge_class(%{state: :blocked}), do: "badge-error badge-outline"
  defp source_selection_badge_class(_selection), do: "badge-warning badge-outline"

  defp source_selection_candidate_class(%{decision: :selected}), do: "badge-success"
  defp source_selection_candidate_class(%{decision: :rejected}), do: "badge-error badge-outline"
  defp source_selection_candidate_class(%{decision: :not_selected}), do: "badge-ghost"
  defp source_selection_candidate_class(_candidate), do: "badge-info badge-outline"

  defp source_selection_candidate_reason(%{reasons_text: reasons}) when reasons not in [nil, ""],
    do: reasons

  defp source_selection_candidate_reason(%{source_health_reason_text: reason})
       when reason not in [nil, ""],
       do: reason

  defp source_selection_candidate_reason(_candidate), do: "none"

  defp source_selection_candidate_products(%{missing_products_text: missing} = candidate)
       when missing not in [nil, ""] do
    [
      "missing products=#{missing}",
      source_selection_candidate_product_part(
        "requested",
        Map.get(candidate, :requested_products_text)
      ),
      source_selection_candidate_product_part(
        "supported",
        Map.get(candidate, :supported_products_text)
      )
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp source_selection_candidate_products(_candidate), do: ""

  defp source_selection_candidate_product_part(_label, value) when value in [nil, ""], do: nil
  defp source_selection_candidate_product_part(label, value), do: "#{label}=#{value}"

  defp source_selection_candidate_window(%{started_at_text: start_time, ended_at_text: end_time})
       when start_time not in [nil, ""] and end_time not in [nil, ""] do
    "#{start_time} -> #{end_time}"
  end

  defp source_selection_candidate_window(%{started_at_text: start_time})
       when start_time not in [nil, ""] do
    "#{start_time} -> open"
  end

  defp source_selection_candidate_window(%{ended_at_text: end_time})
       when end_time not in [nil, ""] do
    "unknown -> #{end_time}"
  end

  defp source_selection_candidate_window(_candidate), do: ""

  defp source_selection_candidate_action(%{inventory_query: query})
       when is_map(query) and map_size(query) > 0,
       do: "source_inventory"

  defp source_selection_candidate_action(_candidate), do: "none"

  defp source_selection_candidate_query(%{inventory_query: query})
       when is_map(query) and map_size(query) > 0 do
    query
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("&", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp source_selection_candidate_query(_candidate), do: ""

  defp source_selection_candidate_href(mission_id, %{inventory_query: query})
       when is_binary(mission_id) and mission_id != "" and is_map(query) and map_size(query) > 0 do
    ~p"/missions/#{mission_id}/ops/data-sources?#{query}"
  end

  defp source_selection_candidate_href(_mission_id, _candidate), do: nil
end
