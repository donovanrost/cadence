defmodule CadenceWeb.OpsDashboardShowLive.SourceSelectionComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :selections, :list, required: true
  attr :mission_id, :string, default: nil

  def source_selection_strip(assigns) do
    assigns =
      assign(
        assigns,
        :source_selection_presentation,
        source_selection_presentation(assigns.selections, Map.get(assigns, :mission_id))
      )

    ~H"""
    <.vue
      :if={@selections != []}
      id="dashboard-source-selection-component"
      v-component="SourceSelection"
      presentation={@source_selection_presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp source_selection_presentation(selections, mission_id) do
    %{
      id: "dashboard-source-selection",
      class:
        "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-base-300/60 bg-base-200/30 text-xs",
      label: %{text: "Source selection", class: "hud-label"},
      attrs: %{
        "data-source-selection-requests" => Integer.to_string(length(selections)),
        "data-source-selection-request-ids" => source_selection_request_ids(selections),
        "data-source-selection-bindings" => source_selection_bindings(selections),
        "data-source-selection-data-sources" => source_selection_data_sources(selections),
        "data-source-selection-rejected" =>
          selections |> source_selection_rejected_count() |> Integer.to_string()
      },
      selections: Enum.map(selections, &source_selection_dto(&1, mission_id))
    }
  end

  defp source_selection_dto(selection, mission_id) do
    request_id = source_selection_text(selection, :request_id)
    logical_source_text = source_selection_text(selection, :logical_source_text)
    overlay_id = "source-selection-#{request_id}"
    badge_class = source_selection_badge_class(selection)

    %{
      overlay: %{
        id: overlay_id,
        class: "cadence-overlay",
        trigger_id: "#{overlay_id}-trigger",
        trigger_class: "cadence-overlay-trigger",
        panel_id: "#{overlay_id}-panel",
        panel_class: "cadence-overlay-panel cadence-popover-panel",
        placement: "bottom-end",
        width: "lg",
        label: "#{logical_source_text} source selection",
        attrs: %{"data-source-selection-detail" => request_id}
      },
      badge: %{
        class: "badge badge-xs cursor-pointer gap-1 #{badge_class}",
        title: source_selection_title(selection),
        label: logical_source_text,
        icon: %{name: "hero-adjustments-horizontal", class: "h-3 w-3"},
        attrs: %{
          "data-source-selection" => request_id,
          "data-source-selection-state" => source_selection_text(selection, :state_text),
          "data-source-selection-logical-source" => logical_source_text,
          "data-source-selection-binding" =>
            source_selection_text(selection, :selected_binding_id),
          "data-source-selection-data-source" =>
            source_selection_text(selection, :selected_data_source_id),
          "data-source-selection-candidates" =>
            source_selection_text(selection, :candidate_count),
          "data-source-selection-eligible" =>
            source_selection_text(selection, :eligible_candidate_count),
          "data-source-selection-rejected" =>
            source_selection_text(selection, :rejected_candidate_count)
        }
      },
      details: %{
        class: "p-2 text-xs",
        header_class: "flex items-start justify-between gap-2",
        identity_class: "min-w-0",
        heading: %{
          text: "#{logical_source_text} source selection",
          class: "font-semibold text-base-content"
        },
        request_id: %{
          text: request_id,
          class: "mt-0.5 font-mono text-[0.68rem] text-base-content/60"
        },
        state: %{
          text: source_selection_text(selection, :state_text),
          class: "badge badge-xs #{badge_class}"
        },
        facts_class: "mt-2 grid grid-cols-[8rem_minmax(0,1fr)] gap-x-2 gap-y-1",
        facts: source_selection_facts(selection),
        candidates_class: "mt-2 overflow-hidden rounded border border-base-300/70"
      },
      candidates:
        selection
        |> Map.get(:candidates, [])
        |> Enum.with_index()
        |> Enum.map(fn {candidate, index} ->
          source_selection_candidate_dto(candidate, mission_id, index)
        end)
    }
  end

  defp source_selection_facts(selection) do
    [
      source_selection_fact("Strategy", source_selection_text(selection, :strategy_text)),
      source_selection_fact(
        "Selected binding",
        source_selection_text(selection, :selected_binding_id),
        true
      ),
      source_selection_fact(
        "Selected source",
        source_selection_text(selection, :selected_data_source_id),
        true
      ),
      source_selection_optional_fact("Dataset", selection, :selected_dataset, true),
      source_selection_optional_fact("Requested realm", selection, :requested_realm),
      source_selection_fact(
        "Candidates",
        "#{source_selection_text(selection, :eligible_candidate_count)}/#{source_selection_text(selection, :candidate_count)} eligible"
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp source_selection_fact(label, value, break? \\ false) do
    %{
      label: label,
      value: value,
      label_class: "text-base-content/60",
      value_class:
        if(break?,
          do: "font-mono text-base-content break-all",
          else: "font-mono text-base-content"
        )
    }
  end

  defp source_selection_optional_fact(label, selection, key, break? \\ false) do
    case Map.get(selection, key) do
      value when value in [nil, false] -> nil
      value -> source_selection_fact(label, source_selection_value_text(value), break?)
    end
  end

  defp source_selection_candidate_dto(candidate, mission_id, index) do
    binding_id = source_selection_fallback_text(candidate, :binding_id)
    data_source_id = source_selection_fallback_text(candidate, :data_source_id)
    window_text = source_selection_candidate_window(candidate)
    product_summary = source_selection_candidate_products(candidate)

    %{
      key: "source-selection-candidate-#{index}",
      class:
        "grid grid-cols-[minmax(0,1.1fr)_minmax(0,1.1fr)_5rem_minmax(0,0.9fr)_minmax(0,1.2fr)_auto] gap-2 border-b border-base-300/60 px-2 py-1 last:border-b-0",
      attrs: %{
        "data-source-selection-candidate" => binding_id,
        "data-source-selection-candidate-source" => data_source_id,
        "data-source-selection-candidate-decision" =>
          source_selection_fallback_text(candidate, :decision_text),
        "data-source-selection-candidate-reasons" =>
          source_selection_fallback_text(candidate, :reasons_text),
        "data-source-selection-candidate-window" => window_text,
        "data-source-selection-candidate-health" =>
          source_selection_fallback_text(candidate, :source_health_text),
        "data-source-selection-candidate-freshness" =>
          source_selection_fallback_text(candidate, :source_health_freshness_text),
        "data-source-selection-candidate-requested-products" =>
          source_selection_optional_attr(candidate, :requested_products_text),
        "data-source-selection-candidate-supported-products" =>
          source_selection_optional_attr(candidate, :supported_products_text),
        "data-source-selection-candidate-missing-products" =>
          source_selection_optional_attr(candidate, :missing_products_text),
        "data-source-selection-candidate-action" => source_selection_candidate_action(candidate),
        "data-source-selection-candidate-action-query" =>
          source_selection_candidate_query(candidate)
      },
      binding: %{
        text: source_selection_text(candidate, :binding_id),
        class: "min-w-0 truncate font-mono text-base-content"
      },
      data_source: %{
        text: source_selection_text(candidate, :data_source_id),
        class: "min-w-0 truncate font-mono text-base-content/70"
      },
      decision: %{
        text: source_selection_fallback_text(candidate, :decision_text),
        class: "badge badge-xs #{source_selection_candidate_class(candidate)}"
      },
      reason: %{
        text:
          candidate
          |> source_selection_candidate_reason()
          |> source_selection_value_text(),
        class: "min-w-0 truncate font-mono text-base-content/60"
      },
      window: %{
        text: window_text,
        class: "min-w-0 truncate font-mono text-base-content/60"
      },
      action: source_selection_candidate_action_dto(mission_id, candidate),
      product_summary: source_selection_candidate_product_dto(candidate, product_summary)
    }
  end

  defp source_selection_candidate_action_dto(mission_id, candidate) do
    case source_selection_candidate_href(mission_id, candidate) do
      nil ->
        nil

      href ->
        %{
          href: href,
          class: "btn btn-ghost btn-xs gap-1",
          title:
            source_selection_fallback_value(
              Map.get(candidate, :inventory_action_label),
              "Open source inventory"
            )
            |> source_selection_value_text(),
          label: "Open",
          icon: %{name: "hero-arrow-top-right-on-square", class: "h-3.5 w-3.5"},
          attrs: %{
            "data-phx-link" => "redirect",
            "data-phx-link-state" => "push",
            "data-source-selection-candidate-open" =>
              source_selection_candidate_identity(candidate)
          }
        }
    end
  end

  defp source_selection_candidate_product_dto(_candidate, ""), do: nil

  defp source_selection_candidate_product_dto(candidate, product_summary) do
    %{
      text: product_summary,
      class: "col-span-full min-w-0 truncate font-mono text-[0.68rem] text-warning",
      attrs: %{
        "data-source-selection-candidate-product-summary" =>
          source_selection_candidate_identity(candidate)
      }
    }
  end

  defp source_selection_candidate_identity(candidate) do
    source_selection_fallback_value(
      Map.get(candidate, :binding_id),
      source_selection_fallback_value(Map.get(candidate, :data_source_id), "")
    )
    |> source_selection_value_text()
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

  defp source_selection_fallback_text(selection, key) when is_map(selection) do
    selection
    |> Map.get(key)
    |> source_selection_fallback_value("")
    |> source_selection_value_text()
  end

  defp source_selection_optional_attr(selection, key) do
    case Map.fetch(selection, key) do
      :error -> ""
      {:ok, value} when value in [nil, false] -> nil
      {:ok, value} -> source_selection_value_text(value)
    end
  end

  defp source_selection_fallback_value(value, fallback) when value in [nil, false], do: fallback
  defp source_selection_fallback_value(value, _fallback), do: value

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
