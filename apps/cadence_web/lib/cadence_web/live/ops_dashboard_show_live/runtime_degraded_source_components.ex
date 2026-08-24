defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs

  attr(:summary, :map, required: true)

  def degraded_source_summary(%{summary: %{visible?: true} = summary} = assigns) do
    assigns = assign(assigns, :presentation, degraded_source_summary_presentation(summary))

    ~H"""
    <.vue
      id="dashboard-source-execution-degraded-summary-component"
      v-component="RuntimeDegradedSource"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def degraded_source_summary(assigns), do: ~H""

  attr(:drilldowns, :list, required: true)

  def degraded_source_drilldowns(%{drilldowns: drilldowns} = assigns)
      when is_list(drilldowns) and drilldowns != [] do
    assigns = assign(assigns, :presentation, degraded_source_drilldowns_presentation(drilldowns))

    ~H"""
    <.vue
      id="dashboard-degraded-source-drilldowns-component"
      v-component="RuntimeDegradedSource"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def degraded_source_drilldowns(assigns), do: ~H""

  attr(:postures, :list, default: [])

  def source_capability_postures(%{postures: postures} = assigns)
      when is_list(postures) and postures != [] do
    assigns = assign(assigns, :presentation, source_capability_postures_presentation(postures))

    ~H"""
    <.vue
      id="dashboard-source-capability-postures-component"
      v-component="RuntimeDegradedSource"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def source_capability_postures(assigns), do: ~H""

  attr(:dependencies, :list, default: [])

  def source_dependency_causes(%{dependencies: dependencies} = assigns)
      when is_list(dependencies) and dependencies != [] do
    assigns = assign(assigns, :presentation, source_dependency_causes_presentation(dependencies))

    ~H"""
    <.vue
      id="dashboard-source-dependency-causes-component"
      v-component="RuntimeDegradedSource"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def source_dependency_causes(assigns), do: ~H""

  def degraded_source_summary_presentation(summary) do
    %{
      kind: "summary",
      root: %{
        id: "dashboard-source-execution-degraded-summary",
        class: "border border-warning/30 bg-warning/10 px-3 py-2 text-sm",
        attrs: %{
          "data-diagnostics-section" => "Source execution degraded",
          "data-source-execution-degraded-count" => attribute_value(Map.get(summary, :count)),
          "data-source-execution-degraded-identity" =>
            attribute_value(Map.get(summary, :identity)),
          "data-source-execution-degraded-status" => attribute_value(Map.get(summary, :status)),
          "data-source-execution-runtime-action" =>
            attribute_value(Map.get(summary, :runtime_action)),
          "data-source-execution-operator-action" =>
            attribute_value(Map.get(summary, :operator_action)),
          "data-source-execution-realm" => attribute_value(Map.get(summary, :realm)),
          "data-source-execution-data-source" =>
            attribute_value(Map.get(summary, :data_source_id)),
          "data-source-execution-binding" =>
            attribute_value(Map.get(summary, :source_binding_id)),
          "data-source-execution-request" => attribute_value(Map.get(summary, :request_id))
        }
      },
      heading: %{text: "Source execution degraded", class: "hud-label"},
      headline: %{
        text: value_text(Map.get(summary, :headline)),
        class: "mt-1 text-base-content"
      },
      fields_class: "mt-2 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
      fields: [
        summary_field("Source", Map.get(summary, :identity)),
        summary_field("Status", Map.get(summary, :status)),
        summary_field("Runtime", Map.get(summary, :runtime_action)),
        summary_field("Operator", Map.get(summary, :operator_action))
      ]
    }
  end

  defp summary_field(label, value) do
    %{
      key: label,
      label: %{text: label, class: "text-base-content/60"},
      value: %{
        text: value_text(value),
        class: "font-mono text-base-content break-all",
        attrs: %{"data-source-execution-field" => label}
      }
    }
  end

  def degraded_source_drilldowns_presentation(drilldowns) do
    %{
      kind: "drilldowns",
      root: %{
        id: nil,
        class: "space-y-2",
        attrs: %{"data-diagnostics-section" => "Degraded sources"}
      },
      heading: %{text: "Degraded sources", class: "hud-label"},
      items_container: %{id: "dashboard-degraded-source-drilldowns", class: "space-y-2"},
      items:
        drilldowns
        |> Enum.with_index()
        |> Enum.map(fn {drilldown, index} -> degraded_source_drilldown_dto(drilldown, index) end)
    }
  end

  defp degraded_source_drilldown_dto(drilldown, index) do
    attrs = %{
      "phx-click" => "open_evidence",
      "data-degraded-source-drilldown" => attribute_value(Map.get(drilldown, :request_id)),
      "data-degraded-source-logical-source" =>
        attribute_value(Map.get(drilldown, :logical_source)),
      "data-degraded-source-status" => attribute_value(Map.get(drilldown, :status)),
      "data-degraded-source-runtime-action" =>
        attribute_value(Map.get(drilldown, :runtime_action)),
      "data-degraded-source-operator-action" =>
        attribute_value(Map.get(drilldown, :operator_action))
    }

    evidence_attrs = EvidenceAttrs.degraded_source(drilldown)

    %{
      key: "degraded-source-drilldown-#{index}",
      type: "button",
      class:
        "w-full border border-warning/30 bg-warning/5 px-2 py-2 text-left text-xs hover:bg-warning/10",
      attrs: attrs,
      evidence_attrs: evidence_attrs,
      render_attrs: Map.merge(attrs, evidence_attrs),
      primary: %{
        class: "flex items-center gap-2",
        icon: %{name: "hero-document-magnifying-glass", class: "h-3.5 w-3.5 text-warning"},
        text: %{
          text: degraded_source_label(drilldown),
          class: "font-mono text-base-content break-all"
        }
      },
      fields: [
        %{
          key: "actions",
          text: degraded_source_actions(drilldown),
          class: "mt-1 block font-mono text-base-content/60 break-all",
          attrs: %{}
        }
      ]
    }
  end

  def source_capability_postures_presentation(postures) do
    %{
      kind: "capability_postures",
      root: %{
        id: "dashboard-source-capability-postures",
        class: "space-y-2",
        attrs: %{
          "data-diagnostics-section" => "Source capability posture",
          "data-source-capability-posture-count" => Integer.to_string(length(postures))
        }
      },
      heading: %{text: "Source capability posture", class: "hud-label"},
      items_container: %{id: nil, class: "space-y-2"},
      items:
        postures
        |> Enum.with_index()
        |> Enum.map(fn {posture, index} -> source_capability_posture_dto(posture, index) end)
    }
  end

  defp source_capability_posture_dto(posture, index) do
    attrs = %{
      "phx-click" => "open_evidence",
      "data-source-capability-posture" => attribute_value(Map.get(posture, :request_id)),
      "data-source-capability-logical-source" =>
        attribute_value(Map.get(posture, :logical_source)),
      "data-source-capability-status" => attribute_value(Map.get(posture, :status)),
      "data-source-capability-requested-axis" =>
        attribute_value(Map.get(posture, :requested_time_axis)),
      "data-source-capability-executed-axis" =>
        attribute_value(Map.get(posture, :executed_time_axis)),
      "data-source-capability-supported-axes" =>
        attribute_value(Map.get(posture, :supported_time_axes)),
      "data-source-capability-requested-products" =>
        attribute_value(Map.get(posture, :requested_products)),
      "data-source-capability-supported-products" =>
        attribute_value(Map.get(posture, :supported_products))
    }

    evidence_attrs = EvidenceAttrs.source_capability_posture(posture)

    %{
      key: "source-capability-posture-#{index}",
      type: "button",
      class:
        "w-full border border-base-content/15 bg-base-200/40 px-2 py-2 text-left text-xs hover:bg-base-200/70",
      attrs: attrs,
      evidence_attrs: evidence_attrs,
      render_attrs: Map.merge(attrs, evidence_attrs),
      primary: %{
        class: "flex items-center gap-2",
        icon: %{
          name: source_capability_icon(posture),
          class: "h-3.5 w-3.5 #{source_capability_icon_class(posture)}"
        },
        text: %{
          text: source_capability_headline(posture),
          class: "font-medium text-base-content"
        }
      },
      fields: [
        %{
          key: "clock",
          text: source_capability_clock(posture),
          class: "mt-1 block font-mono text-base-content break-all",
          attrs: %{"data-source-capability-field" => "Clock"}
        },
        %{
          key: "support",
          text: source_capability_support(posture),
          class: "mt-1 block font-mono text-base-content/60 break-all",
          attrs: %{"data-source-capability-field" => "Support"}
        }
      ]
    }
  end

  def source_dependency_causes_presentation(dependencies) do
    %{
      kind: "dependency_causes",
      root: %{
        id: "dashboard-source-dependency-causes",
        class: "space-y-2",
        attrs: %{
          "data-diagnostics-section" => "Source dependency causes",
          "data-source-dependency-cause-count" => Integer.to_string(length(dependencies))
        }
      },
      heading: %{text: "Source dependency causes", class: "hud-label"},
      items_container: %{id: nil, class: "space-y-2"},
      items:
        dependencies
        |> Enum.with_index()
        |> Enum.map(fn {dependency, index} -> source_dependency_cause_dto(dependency, index) end)
    }
  end

  defp source_dependency_cause_dto(dependency, index) do
    attrs = %{
      "phx-click" => "open_evidence",
      "data-source-dependency-cause" => attribute_value(Map.get(dependency, :request_id)),
      "data-source-dependency-request-source" =>
        attribute_value(Map.get(dependency, :request_logical_source)),
      "data-source-dependency-upstream-source" =>
        attribute_value(Map.get(dependency, :logical_source)),
      "data-source-dependency-upstream-request" =>
        attribute_value(Map.get(dependency, :upstream_request_id)),
      "data-source-dependency-upstream-status" =>
        attribute_value(Map.get(dependency, :upstream_status)),
      "data-source-dependency-upstream-runtime-action" =>
        attribute_value(Map.get(dependency, :upstream_runtime_action)),
      "data-source-dependency-upstream-watermark-state" =>
        attribute_value(Map.get(dependency, :upstream_watermark_freshness_state))
    }

    evidence_attrs =
      dependency
      |> upstream_source_evidence()
      |> EvidenceAttrs.degraded_source()

    %{
      key: "source-dependency-cause-#{index}",
      type: "button",
      class:
        "w-full border border-warning/30 bg-warning/5 px-2 py-2 text-left text-xs hover:bg-warning/10",
      attrs: attrs,
      evidence_attrs: evidence_attrs,
      render_attrs: Map.merge(attrs, evidence_attrs),
      primary: %{
        class: "flex items-center gap-2",
        icon: %{name: "hero-arrow-path", class: "h-3.5 w-3.5 text-warning"},
        text: %{
          text: dependency_cause_headline(dependency),
          class: "font-medium text-base-content"
        }
      },
      fields: [
        %{
          key: "path",
          text: dependency_path(dependency),
          class: "mt-1 block font-mono text-base-content break-all",
          attrs: %{"data-source-dependency-field" => "Path"}
        },
        %{
          key: "upstream",
          text: dependency_upstream_state(dependency),
          class: "mt-1 block font-mono text-base-content/60 break-all",
          attrs: %{"data-source-dependency-field" => "Upstream"}
        }
      ]
    }
  end

  defp degraded_source_label(drilldown) do
    [
      Map.get(drilldown, :logical_source),
      Map.get(drilldown, :request_id),
      Map.get(drilldown, :status)
    ]
    |> joined_values(":")
  end

  defp degraded_source_actions(drilldown) do
    [
      Map.get(drilldown, :runtime_action),
      Map.get(drilldown, :operator_action)
    ]
    |> joined_values(":")
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
    |> joined_values(":")
  end

  defp source_capability_clock(posture) do
    [
      Map.get(posture, :requested_time_axis),
      "->",
      Map.get(posture, :executed_time_axis)
    ]
    |> joined_values(" ")
  end

  defp source_capability_support(posture) do
    [
      supported_values("sampling", Map.get(posture, :supported_sampling)),
      supported_values("products", Map.get(posture, :supported_products)),
      supported_values("axes", Map.get(posture, :supported_time_axes)),
      details_value("fallback", Map.get(posture, :fallbacks)),
      details_value("unsupported", Map.get(posture, :unsupported))
    ]
    |> joined_values(" ")
  end

  defp supported_values(_label, value) when value in [nil, ""], do: nil
  defp supported_values(label, value), do: "#{label}=#{value_text(value)}"

  defp details_value(_label, value) when value in [nil, ""], do: nil
  defp details_value(label, value), do: "#{label}=#{value_text(value)}"

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
    |> joined_values(" ")
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
    |> joined_values(" ")
  end

  defp dependency_identity(nil, request_id), do: value_text(request_id)
  defp dependency_identity(source, nil), do: value_text(source)

  defp dependency_identity(source, request_id),
    do: "#{value_text(source)}:#{value_text(request_id)}"

  defp dependency_upstream_state(dependency) do
    [
      Map.get(dependency, :upstream_status),
      Map.get(dependency, :upstream_runtime_action),
      Map.get(dependency, :upstream_watermark_freshness_state)
    ]
    |> joined_values(":")
  end

  defp joined_values(values, separator) do
    values
    |> Enum.reject(&blank?/1)
    |> Enum.map(&value_text/1)
    |> Enum.join(separator)
  end

  defp attribute_value(nil), do: nil
  defp attribute_value(value), do: value_text(value)

  defp value_text(nil), do: ""
  defp value_text(value) when is_binary(value), do: value
  defp value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp value_text(value) when is_integer(value), do: Integer.to_string(value)
  defp value_text(value) when is_float(value), do: Float.to_string(value)
  defp value_text(value), do: inspect(value)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
