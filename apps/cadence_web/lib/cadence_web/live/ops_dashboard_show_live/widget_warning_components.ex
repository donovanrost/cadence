defmodule CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.{DataLinkAttrs, EvidenceAttrs}

  @overlay_class "cadence-overlay"
  @trigger_class "cadence-overlay-trigger"
  @panel_class "cadence-overlay-panel cadence-popover-panel"
  @body_class "p-2 text-xs"
  @evidence_button_class "mt-2 btn btn-xs btn-outline w-full justify-start"
  @evidence_icon %{
    name: "hero-document-magnifying-glass",
    class: "h-3.5 w-3.5"
  }
  @detail_list_class "mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1"
  @evidence_list_class "mt-2 space-y-1"
  @evidence_row_class "grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1"
  @link_list_class "mt-2 space-y-1"
  @link_class "grid w-full grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left hover:border-primary/60 hover:bg-base-200"

  attr :id, :string, required: true
  attr :warning, :map, required: true
  attr :placement_id, :string, default: nil

  def engine_warning_badge(assigns) do
    presentation = warning_presentation(assigns.id, assigns.warning, assigns.placement_id)
    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetWarning"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def warning_codes(warnings) when is_list(warnings) do
    Enum.map_join(warnings, ",", & &1.code_text)
  end

  def warning_codes(_warnings), do: ""

  defp warning_presentation(id, warning, placement_id) do
    label = text_value(warning.label)

    %{
      component_id: "#{id}-component",
      overlay: %{
        id: id,
        class: @overlay_class,
        attrs:
          compact_attrs(%{
            "data-overlay-kind" => "popover",
            "data-overlay-placement" => "bottom-end",
            "data-engine-warning-detail" => direct_attr_value(warning.code_text),
            "data-limit-selected-clock" =>
              direct_attr_value(warning_detail_value(warning, :selected_limit_clock)),
            "data-limit-missing-samples" =>
              direct_attr_value(warning_detail_value(warning, :missing_sample_ids)),
            "data-limit-mode" =>
              direct_attr_value(warning_detail_value(warning, :requested_semantics_mode))
          })
      },
      trigger: %{
        id: "#{id}-trigger",
        type: "button",
        class: @trigger_class,
        attrs:
          compact_attrs(%{
            "data-overlay-trigger" => "",
            "aria-haspopup" => "dialog",
            "aria-expanded" => "false",
            "aria-controls" => "#{id}-panel",
            "aria-label" => direct_attr_value(warning.label)
          }),
        badge: %{
          class: "badge badge-xs cursor-pointer #{warning_badge_class(warning)}",
          attrs:
            compact_attrs(%{
              "data-engine-warning" => direct_attr_value(warning.code_text),
              "title" => direct_attr_value(warning.message)
            }),
          text: label
        }
      },
      panel: %{
        id: "#{id}-panel",
        class: @panel_class,
        hidden: true,
        attrs:
          compact_attrs(%{
            "data-overlay-panel" => "",
            "data-overlay-width" => "md",
            "aria-label" => direct_attr_value(warning.label)
          })
      },
      body: %{
        class: @body_class,
        heading: %{class: "font-semibold text-base-content", text: label},
        message: %{class: "mt-1 text-base-content/70", text: text_value(warning.message)},
        evidence_button: evidence_button(warning, placement_id),
        details: %{
          visible: warning.detail_rows != [],
          class: @detail_list_class,
          rows:
            warning.detail_rows
            |> Enum.with_index()
            |> Enum.map(&detail_row(&1, id))
        },
        evidence: %{
          visible: warning.evidence != [],
          class: @evidence_list_class,
          attrs: %{"data-warning-evidence" => ""},
          heading: %{class: "font-semibold text-base-content/80", text: "Evidence"},
          rows:
            warning.evidence
            |> Enum.with_index()
            |> Enum.map(&evidence_row(&1, id))
        },
        links: %{
          visible: warning.links != [],
          class: @link_list_class,
          attrs: %{"data-warning-links" => ""},
          heading: %{class: "font-semibold text-base-content/80", text: "Data links"},
          rows:
            warning.links
            |> Enum.with_index()
            |> Enum.map(&link_row(&1, id, placement_id, warning))
        }
      }
    }
  end

  defp evidence_button(warning, placement_id) do
    %{
      type: "button",
      class: @evidence_button_class,
      attrs:
        warning
        |> EvidenceAttrs.warning(placement_id)
        |> Map.merge(%{
          "phx-click" => "open_evidence",
          "data-warning-evidence-open" => ""
        }),
      icon: @evidence_icon,
      text: "Inspect evidence"
    }
  end

  defp detail_row({row, index}, id) do
    %{
      key: "#{id}-detail-#{index}",
      label: %{class: "text-base-content/60", text: text_value(row.label)},
      value: %{
        class: "font-mono text-base-content break-all",
        attrs: compact_attrs(%{"data-warning-detail" => direct_attr_value(row.label)}),
        text: text_value(row.value)
      }
    }
  end

  defp evidence_row({evidence, index}, id) do
    %{
      key: "#{id}-evidence-#{index}",
      class: @evidence_row_class,
      attrs:
        compact_attrs(%{
          "data-warning-evidence-kind" => direct_attr_value(evidence.kind_text),
          "data-warning-evidence-id" => fallback_attr_value(evidence.id)
        }),
      fields: [
        field("#{id}-evidence-#{index}-kind", evidence.kind_text, evidence.id),
        field("#{id}-evidence-#{index}-source", "Source", evidence.source_text),
        field("#{id}-evidence-#{index}-observed", "Observed", evidence.observed_at_text)
      ]
    }
  end

  defp link_row({link, index}, id, placement_id, warning) do
    %{
      key: "#{id}-link-#{index}",
      type: "button",
      class: @link_class,
      attrs:
        link
        |> DataLinkAttrs.open(
          placement_id: placement_id,
          context_fallback: warning_data_link_context_fallback(warning)
        )
        |> Map.merge(%{
          "phx-click" => "open_data_link",
          "data-warning-link-target" => direct_attr_value(link.target_text),
          "data-warning-link-id" => fallback_attr_value(link.target_id),
          "data-warning-link-ref" => fallback_attr_value(link.link_id)
        })
        |> compact_attrs(),
      fields: [
        field("#{id}-link-#{index}-target", link.target_text, link.target_id),
        field("#{id}-link-#{index}-source", "Source", link.source_text)
      ]
    }
  end

  defp field(key, label, value) do
    %{
      key: key,
      label: %{class: "text-base-content/60", text: text_value(label)},
      value: %{class: "font-mono text-base-content break-all", text: text_value(value)}
    }
  end

  defp warning_badge_class(%{severity: :error}), do: "badge-error"
  defp warning_badge_class(%{severity: :warning}), do: "badge-warning"
  defp warning_badge_class(_warning), do: "badge-info"

  defp warning_data_link_context_fallback(%{details: details}) when is_map(details), do: details
  defp warning_data_link_context_fallback(_warning), do: %{}

  defp warning_detail_value(%{details: details}, key) when is_map(details) do
    details
    |> Map.get(key, Map.get(details, Atom.to_string(key)))
    |> warning_detail_text()
  end

  defp warning_detail_value(_warning, _key), do: nil

  defp warning_detail_text(nil), do: nil
  defp warning_detail_text(value) when is_atom(value), do: Atom.to_string(value)
  defp warning_detail_text(value) when is_binary(value), do: value

  defp warning_detail_text(values) when is_list(values),
    do: Enum.map_join(values, ",", &warning_detail_text/1)

  defp warning_detail_text(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      "#{warning_detail_text(key)}=#{warning_detail_text(nested_value)}"
    end)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp warning_detail_text(value), do: to_string(value)

  defp compact_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp direct_attr_value(value) when value in [nil, false], do: nil
  defp direct_attr_value(true), do: ""
  defp direct_attr_value(value), do: text_value(value)

  defp fallback_attr_value(value), do: direct_attr_value(value || "")

  defp text_value(nil), do: ""
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)
end
