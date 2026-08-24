defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation

  attr(:inspector, :map, required: true)
  attr(:mission_id, :string, required: true)
  attr(:dashboard_document, :any, required: true)
  attr(:dashboard_current_path, :string, required: true)
  attr(:data_link_action_outcome, :map, default: nil)

  def data_link_panel(assigns) do
    presentation =
      DataLinkInspectorPanelPresentation.for_vue(
        assigns.inspector,
        assigns.mission_id,
        assigns.dashboard_document,
        assigns.dashboard_current_path,
        assigns.data_link_action_outcome
      )

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <div
      id="dashboard-data-link-inspector"
      data-data-link-target={@presentation.root.attrs["data-data-link-target"]}
      data-data-link-target-id={@presentation.root.attrs["data-data-link-target-id"]}
      data-data-link-status={@presentation.root.attrs["data-data-link-status"]}
      data-data-link-selected-link={@presentation.root.attrs["data-data-link-selected-link"]}
      data-data-link-selected-realm={@presentation.root.attrs["data-data-link-selected-realm"]}
      data-data-link-selected-data-view={@presentation.root.attrs["data-data-link-selected-data-view"]}
      data-data-link-selected-data-source-id={@presentation.root.attrs["data-data-link-selected-data-source-id"]}
      data-data-link-selected-source-binding-id={@presentation.root.attrs["data-data-link-selected-source-binding-id"]}
      data-data-link-selected-time-mode={@presentation.root.attrs["data-data-link-selected-time-mode"]}
      data-data-link-selected-time-axis={@presentation.root.attrs["data-data-link-selected-time-axis"]}
      data-data-link-selected-replay-run-id={@presentation.root.attrs["data-data-link-selected-replay-run-id"]}
      class="space-y-4"
    >
      <.vue
        id="dashboard-data-link-inspector-component"
        v-component="DataLinkInspectorPanel"
        presentation={@presentation}
        v-ssr={false}
        class="space-y-4"
      />
    </div>
    """
  end
end
