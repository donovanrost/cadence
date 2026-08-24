defmodule CadenceWeb.OpsDashboardShowLive.SourceHealthComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs

  @root_class "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-base-300/60 bg-base-200/40 text-xs"
  @overlay_class "cadence-overlay"
  @trigger_class "cadence-overlay-trigger"
  @panel_class "cadence-overlay-panel cadence-popover-panel"
  @badge_class "badge badge-xs cursor-pointer"
  @evidence_button_class "mt-2 btn btn-xs btn-outline w-full justify-start"

  attr(:health, :list, required: true)

  def source_health_strip(%{health: [_source | _] = health} = assigns) do
    assigns = assign(assigns, :presentation, source_health_dto(health))

    ~H"""
    <.vue
      id="dashboard-source-health-component"
      v-component="SourceHealth"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def source_health_strip(_assigns), do: ~H""

  defp source_health_dto(health) do
    %{
      root: %{
        id: "dashboard-source-health",
        class: @root_class,
        attrs: %{
          "data-source-health" => source_health_codes(health),
          "data-source-cache" => source_cache_codes(health),
          "data-source-circuit" => source_circuit_codes(health),
          "data-source-execution" => source_execution_codes(health),
          "data-source-execution-severity" => source_execution_severity_codes(health),
          "data-source-execution-action" => source_execution_action_codes(health)
        }
      },
      label: %{class: "hud-label", text: "Source status"},
      sources:
        health
        |> Enum.with_index()
        |> Enum.map(fn {source, index} -> source_health_source_dto(source, index) end)
    }
  end

  defp source_health_source_dto(source, index) do
    overlay_id = source_health_overlay_id(source)
    label = Map.get(source, :label)

    %{
      key: "#{overlay_id}-#{index}",
      order: index,
      overlay: %{
        id: overlay_id,
        label: text_value(label),
        class: @overlay_class,
        placement: "bottom-end",
        width: "md",
        attrs:
          compact_direct_attrs(%{
            "data-overlay-kind" => "popover",
            "data-overlay-placement" => "bottom-end",
            "data-source-health-detail" =>
              "#{text_value(Map.get(source, :logical_source_text))}:#{text_value(Map.get(source, :state_text))}",
            "data-source-cache-detail" =>
              "#{text_value(Map.get(source, :logical_source_text))}:#{text_value(Map.get(source, :source_cache_text))}",
            "data-source-circuit-detail" =>
              "#{text_value(Map.get(source, :logical_source_text))}:#{text_value(Map.get(source, :circuit_state_text))}",
            "data-source-execution-detail" =>
              "#{text_value(Map.get(source, :logical_source_text))}:#{text_value(Map.get(source, :execution_status_text))}",
            "data-source-execution-action-detail" =>
              "#{text_value(Map.get(source, :logical_source_text))}:#{text_value(Map.get(source, :execution_operator_action_text))}"
          })
      },
      trigger: %{
        id: "#{overlay_id}-trigger",
        type: "button",
        class: @trigger_class,
        attrs:
          compact_direct_attrs(%{
            "data-overlay-trigger" => "",
            "aria-haspopup" => "dialog",
            "aria-expanded" => "false",
            "aria-controls" => "#{overlay_id}-panel",
            "aria-label" => direct_attr_value(label)
          })
      },
      badge: %{
        class: "#{@badge_class} #{source_health_badge_class(source)}",
        text: text_value(label),
        attrs: source_health_badge_attrs(source, label)
      },
      panel: %{
        id: "#{overlay_id}-panel",
        class: @panel_class,
        hidden: true,
        width: "md",
        attrs:
          compact_direct_attrs(%{
            "data-overlay-panel" => "",
            "data-overlay-width" => "md",
            "aria-label" => direct_attr_value(label)
          })
      },
      details: source_health_details_dto(source, label)
    }
  end

  defp source_health_badge_attrs(source, label) do
    compact_direct_attrs(%{
      "data-source-health-source" => direct_attr_value(Map.get(source, :logical_source_text)),
      "data-source-health-state" => direct_attr_value(Map.get(source, :state_text)),
      "data-source-cache-state" => direct_attr_value(Map.get(source, :source_cache_text)),
      "data-source-frame-cache-state" => direct_attr_value(Map.get(source, :frame_cache_text)),
      "data-source-circuit-state" => direct_attr_value(Map.get(source, :circuit_state_text)),
      "data-source-execution-status" =>
        direct_attr_value(Map.get(source, :execution_status_text)),
      "data-source-execution-severity" =>
        direct_attr_value(Map.get(source, :execution_severity_text)),
      "data-source-execution-action" =>
        direct_attr_value(Map.get(source, :execution_operator_action_text)),
      "data-source-execution-runtime-action" =>
        direct_attr_value(Map.get(source, :execution_runtime_action_text)),
      "data-source-execution-degraded" => truth_text(Map.get(source, :execution_degraded?)),
      "data-source-execution-actionable" => truth_text(Map.get(source, :execution_actionable?)),
      "data-source-execution-retryable" => truth_text(Map.get(source, :execution_retryable?)),
      "title" => direct_attr_value(label)
    })
  end

  defp source_health_details_dto(source, label) do
    %{
      class: "p-2 text-xs",
      heading: %{
        class: "font-semibold text-base-content",
        text: text_value(label)
      },
      prose: %{
        class: "mt-1 text-base-content/70",
        text:
          "Realm #{text_value(Map.get(source, :realm_text))}; confidence #{text_value(Map.get(source, :confidence_text))}; " <>
            "source cache #{status_or_none(Map.get(source, :source_cache_text))}; " <>
            "frame cache #{status_or_none(Map.get(source, :frame_cache_text))}; " <>
            "execution #{status_or_none(Map.get(source, :execution_status_text))}; " <>
            "action #{status_or_none(Map.get(source, :execution_operator_action_text))}."
      },
      circuit: %{
        visible: truthy?(Map.get(source, :circuit_state)),
        class: "mt-1 text-error",
        text:
          "Circuit #{text_value(Map.get(source, :circuit_state_text))}: #{text_value(Map.get(source, :source_warning_text))}"
      },
      evidence: source_health_evidence_dto(source),
      rows_class: "mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1",
      rows:
        source
        |> Map.get(:detail_rows, [])
        |> Enum.with_index()
        |> Enum.map(fn {row, index} -> source_health_detail_row_dto(row, index) end)
    }
  end

  defp source_health_evidence_dto(source) do
    %{
      type: "button",
      class: @evidence_button_class,
      attrs:
        source
        |> EvidenceAttrs.source_health()
        |> Map.merge(%{
          "phx-click" => "open_evidence",
          "data-source-evidence-open" => ""
        }),
      icon: %{
        name: "hero-document-magnifying-glass",
        class: "h-3.5 w-3.5"
      },
      label: "Inspect evidence"
    }
  end

  defp source_health_detail_row_dto(row, index) do
    label = Map.get(row, :label)

    %{
      key: "source-health-detail-row-#{index}",
      order: index,
      label: %{
        class: "text-base-content/60",
        text: text_value(label)
      },
      value: %{
        class: "font-mono text-base-content break-all",
        text: text_value(Map.get(row, :value)),
        attrs:
          compact_direct_attrs(%{
            "data-source-health-field" => direct_attr_value(label)
          })
      }
    }
  end

  defp source_health_overlay_id(source) do
    request_id = Map.get(source, :request_id) || Map.get(source, :logical_source_text)
    data_source_id = Map.get(source, :data_source_id) || "default"

    "source-health-#{text_value(request_id)}-#{text_value(data_source_id)}"
  end

  defp source_health_codes(health) do
    Enum.map_join(health, ",", fn source ->
      "#{text_value(Map.get(source, :logical_source_text))}:#{text_value(Map.get(source, :state_text))}"
    end)
  end

  defp source_cache_codes(health) do
    Enum.map_join(health, ",", fn source ->
      "#{text_value(Map.get(source, :logical_source_text))}:source=#{status_code(Map.get(source, :source_cache_text))};frame=#{status_code(Map.get(source, :frame_cache_text))}"
    end)
  end

  defp source_circuit_codes(health) do
    Enum.map_join(health, ",", fn source ->
      "#{text_value(Map.get(source, :logical_source_text))}:#{status_code(Map.get(source, :circuit_state_text))}"
    end)
  end

  defp source_execution_codes(health) do
    Enum.map_join(health, ",", fn source ->
      "#{text_value(Map.get(source, :logical_source_text))}:#{status_code(Map.get(source, :execution_status_text))}"
    end)
  end

  defp source_execution_severity_codes(health) do
    Enum.map_join(health, ",", fn source ->
      "#{text_value(Map.get(source, :logical_source_text))}:#{status_code(Map.get(source, :execution_severity_text))}"
    end)
  end

  defp source_execution_action_codes(health) do
    Enum.map_join(health, ",", fn source ->
      "#{text_value(Map.get(source, :logical_source_text))}:#{status_code(Map.get(source, :execution_operator_action_text))}"
    end)
  end

  defp status_code(value) when value in [nil, ""], do: "none"
  defp status_code(value), do: value |> text_value() |> String.replace(" ", "_")

  defp status_or_none(value) when value in [nil, ""], do: "none"
  defp status_or_none(value), do: text_value(value)

  # HEEx body values stringify false/true and render nil as empty text.
  defp text_value(value), do: to_string(value)

  # Direct HEEx attributes omit false/nil, preserve empty strings, stringify
  # numbers, and render true as a present valueless attribute.
  defp direct_attr_value(value) when value in [nil, false], do: nil
  defp direct_attr_value(true), do: ""
  defp direct_attr_value(value), do: text_value(value)

  defp compact_direct_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp truth_text(value), do: if(truthy?(value), do: "true", else: "false")
  defp truthy?(value), do: value not in [nil, false]

  defp source_health_badge_class(%{state: :fresh}), do: "badge-success"
  defp source_health_badge_class(%{state: :stale}), do: "badge-warning"
  defp source_health_badge_class(%{state: :retention_gap}), do: "badge-error"
  defp source_health_badge_class(%{state: :unknown}), do: "badge-warning"
  defp source_health_badge_class(_source), do: "badge-info"
end
