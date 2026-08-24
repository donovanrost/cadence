defmodule CadenceWeb.OpsDashboardShowLive.FormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DashboardSectionComponents
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectPanelComponents

  attr(:panel, :any, required: true)
  attr(:dashboard_activity_filter, :atom, default: nil)
  attr(:dashboard_activity_event_id, :string, default: nil)
  attr(:dashboard_review_placement_id, :string, default: nil)
  attr(:dashboard_readiness_return_intent, :string, default: nil)
  attr(:dashboard_selected_publish_issue_id, :string, default: nil)
  attr(:dashboard_comparison_review_action_outcome, :map, default: nil)
  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:binding_preview, :map, default: nil)
  attr(:section_form, Phoenix.HTML.Form, required: true)
  attr(:section_error, :string, default: nil)
  attr(:spacecraft, :list, required: true)
  attr(:operational_observables, :list, required: true)
  attr(:filtered_points, :list, required: true)
  attr(:filtered_operational_observables, :list, required: true)
  attr(:points_empty?, :boolean, required: true)
  attr(:selected_point, :any, required: true)
  attr(:selected_points, :list, required: true)
  attr(:selected_operational_observables, :list, required: true)
  attr(:dashboard_scope_context, :any, required: true)
  attr(:dashboard_editor_focus, :map, default: nil)
  attr(:error, :string, required: true)
  attr(:mission_id, :string, required: true)
  attr(:dashboard_document, :any, required: true)
  attr(:dashboard_summary, :any, required: true)
  attr(:dashboard_versions, :list, required: true)
  attr(:dashboard_lifecycle_events, :list, required: true)
  attr(:dashboard_comparison_review_queue, :map, required: true)
  attr(:dashboard_source_action_events, :list, default: [])
  attr(:dashboard_recent_invalidations, :list, default: [])
  attr(:dashboard_publish_readiness, :map, default: nil)
  attr(:runtime_diagnostics, :map, required: true)
  attr(:dashboard_current_path, :string, required: true)
  attr(:historical_workflow_request_form, Phoenix.HTML.Form, required: true)
  attr(:data_link_action_outcome, :map, default: nil)
  attr(:widget_inspect, :map, default: nil)

  def widget_panel(assigns) do
    assigns = assign(assigns, :presentation, dashboard_panel_presentation(assigns))

    ~H"""
    <.vue
      id="dashboard-panel-component"
      v-component="DashboardPanel"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc "Builds the server-authoritative, JSON-safe dashboard panel presentation."
  def dashboard_panel_presentation(assigns) do
    title = panel_title(assigns.panel)

    %{
      sheet: %{
        layer: %{
          attrs:
            raw_attributes(%{
              "id" => "dashboard-panel-layer",
              "class" => "cadence-sheet-layer"
            })
        },
        root: %{
          attrs:
            raw_attributes(%{
              "id" => "dashboard-panel",
              "role" => "dialog",
              "aria-modal" => "false",
              "aria-label" => title,
              "data-sheet-width" => panel_width(assigns.panel),
              "class" => "cadence-sheet",
              "phx-window-keydown" => "close_panel",
              "phx-key" => "Escape"
            })
        },
        header: %{
          attrs: raw_attributes(%{"class" => "cadence-sheet-header"}),
          title: %{
            attrs: raw_attributes(%{"class" => "hud-label"}),
            text: title
          },
          close: %{
            attrs:
              raw_attributes(%{
                "type" => "button",
                "class" => "cadence-icon-button",
                "phx-click" => "close_panel",
                "aria-label" => "Close panel"
              }),
            icon: %{
              attrs: raw_attributes(%{"class" => "hero-x-mark h-4 w-4"})
            }
          }
        },
        body: %{
          attrs: raw_attributes(%{"class" => "cadence-sheet-body"})
        }
      },
      child: child_presentation(assigns)
    }
  end

  defp child_presentation(%{panel: :rename} = assigns) do
    form =
      to_form(
        %{
          "name" => assigns.dashboard_document.name,
          "description" => assigns.dashboard_document.description
        },
        as: :dashboard
      )

    direct_child(
      "rename_dashboard_form",
      "rename-dashboard-form-component",
      "contents",
      rename_form_presentation(form)
    )
  end

  defp child_presentation(%{panel: :dashboard_sections} = assigns) do
    direct_child(
      "dashboard_section_manager",
      "dashboard-section-manager-component",
      "contents",
      DashboardSectionComponents.section_manager_presentation(%{
        document: assigns.dashboard_document,
        form: assigns.section_form,
        error: assigns.section_error
      })
    )
  end

  defp child_presentation(%{panel: :historical_workflow_request} = assigns) do
    direct_child(
      "historical_workflow_request_form",
      "historical-workflow-request-form-component",
      "contents",
      HistoricalWorkflowRequestFormComponents.request_form_dto(
        assigns.historical_workflow_request_form
      )
    )
  end

  defp child_presentation(%{panel: {:data_link, inspector}} = assigns) do
    presentation =
      DataLinkInspectorPanelPresentation.for_vue(
        inspector,
        assigns.mission_id,
        assigns.dashboard_document,
        assigns.dashboard_current_path,
        assigns.data_link_action_outcome
      )

    direct_child(
      "data_link_inspector_panel",
      "dashboard-data-link-inspector-component",
      "space-y-4",
      presentation,
      presentation.root.attrs
    )
  end

  defp child_presentation(%{panel: {:evidence, inspector}} = assigns) do
    presentation =
      EvidenceInspectorPanelComponents.presentation(%{
        inspector: inspector,
        mission_id: assigns.mission_id,
        dashboard_document: assigns.dashboard_document,
        dashboard_current_path: assigns.dashboard_current_path,
        dashboard_lifecycle_events: assigns.dashboard_lifecycle_events
      })

    direct_child(
      "evidence_inspector_panel",
      presentation.component_id,
      "contents",
      presentation
    )
  end

  defp child_presentation(%{panel: {:widget_inspect, _context}} = assigns) do
    direct_child(
      "widget_inspect_panel",
      "dashboard-widget-inspector-component",
      "contents",
      WidgetInspectPanelComponents.inspect_panel_presentation(assigns.widget_inspect)
    )
  end

  defp child_presentation(%{panel: :diagnostics} = assigns) do
    presentation =
      RuntimeDiagnosticsPanelComponents.presentation(%{
        diagnostics: assigns.runtime_diagnostics,
        dashboard_lifecycle_events: assigns.dashboard_lifecycle_events,
        dashboard_current_path: assigns.dashboard_current_path
      })

    direct_child(
      "runtime_diagnostics_panel",
      "dashboard-diagnostics-panel-component",
      "space-y-5",
      presentation,
      presentation.root.attrs
    )
  end

  defp child_presentation(%{panel: :versions} = assigns) do
    direct_child(
      "version_history_panel",
      "dashboard-version-history-panel-component",
      "contents",
      VersionHistoryPanelComponents.presentation(assigns)
    )
  end

  defp child_presentation(%{panel: :add_widget} = assigns) do
    widget_form_child(assigns)
  end

  defp child_presentation(%{panel: {:edit_placement, _id}} = assigns) do
    widget_form_child(assigns)
  end

  defp widget_form_child(assigns) do
    direct_child(
      "widget_form",
      "widget-form-component",
      "contents",
      WidgetFormComponents.widget_form_dto(assigns)
    )
  end

  defp direct_child(kind, id, class, presentation, outer_attrs \\ nil) do
    %{
      kind: kind,
      outer_wrapper: if(outer_attrs, do: %{attrs: outer_attrs}),
      wrapper: %{
        attrs:
          raw_attributes(%{
            "id" => id,
            "class" => class
          })
      },
      presentation: presentation
    }
  end

  defp rename_form_presentation(form) do
    %{
      root: %{
        attrs:
          raw_attributes(%{
            "id" => "rename-dashboard-form",
            "phx-submit" => "rename",
            "class" => "space-y-4"
          }),
        param: rendered_body(form.name),
        params: active_rename_form_params(form)
      },
      fields: [
        rename_text_field_presentation(form, :name, "Name", required: true),
        rename_text_field_presentation(form, :description, "Description", required: false)
      ],
      submit: %{
        attrs:
          raw_attributes(%{
            "type" => "submit",
            "class" => "btn btn-primary"
          }),
        text: "Save"
      }
    }
  end

  defp rename_text_field_presentation(form, field, label, options) do
    form_field = form[field]

    %{
      key: Atom.to_string(field),
      wrapper: %{attrs: raw_attributes(%{"class" => "fieldset mb-3"})},
      label: %{
        attrs: raw_attributes(%{"class" => "hud-label block mb-1.5"}),
        text: label
      },
      control: %{
        attrs:
          raw_attributes(%{
            "name" => form_field.name,
            "type" => "text",
            "required" => Keyword.fetch!(options, :required),
            "class" => "w-full input"
          }),
        value: nullable_rendered_body(form_field.value)
      }
    }
  end

  defp active_rename_form_params(form) do
    Map.new([:name, :description], fn field ->
      {Atom.to_string(field), rendered_body(form[field].value)}
    end)
  end

  defp panel_width({:widget_inspect, _context}), do: :lg
  defp panel_width(_panel), do: :md

  defp panel_title(:add_widget), do: "Add Widget"
  defp panel_title({:edit_placement, _id}), do: "Configure Widget"
  defp panel_title(:rename), do: "Rename Dashboard"
  defp panel_title(:versions), do: "Version History"
  defp panel_title(:diagnostics), do: "Diagnostics"
  defp panel_title(:dashboard_sections), do: "Dashboard Sections"
  defp panel_title(:historical_workflow_request), do: "Historical Data Request"
  defp panel_title({:data_link, inspector}), do: inspector.title
  defp panel_title({:evidence, inspector}), do: inspector.title
  defp panel_title({:widget_inspect, %{title: title}}), do: "Inspect: #{title}"

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_body(value))
    end)
  end

  defp nullable_rendered_body(nil), do: nil
  defp nullable_rendered_body(value), do: rendered_body(value)

  defp rendered_body(nil), do: ""
  defp rendered_body(value), do: to_string(value)
end
