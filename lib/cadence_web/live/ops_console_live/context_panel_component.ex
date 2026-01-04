defmodule CadenceWeb.OpsConsoleLive.ContextPanelComponent do
  @moduledoc """
  Context panel for OPS Console.

  Displays:
  - Active alarms grouped by severity
  - Command queue summary
  - Quick actions for acknowledging/clearing

  Supports collapsed (rail) and expanded states.
  """

  use CadenceWeb, :live_component

  alias CadenceWeb.OpsConsoleLive.Components, as: OpsComponents

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:alarms, fn -> [] end)
      |> assign_new(:queue_entries, fn -> [] end)
      |> assign_new(:collapsed_sections, fn -> MapSet.new() end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full">
      <OpsComponents.context_panel id="ops-context-panel">
        <:expanded>
          <OpsComponents.context_alarms_section
            alarms={@alarms}
            alarm_counts={@alarm_counts}
            collapsed_sections={@collapsed_sections}
            toggle_target={@myself}
          />

          <OpsComponents.context_queue_section
            queue_entries={@queue_entries}
            collapsed_sections={@collapsed_sections}
            toggle_target={@myself}
          />
        </:expanded>

        <:rail>
          <OpsComponents.context_panel_rail
            alarm_counts={@alarm_counts}
            queue_entries={@queue_entries}
          />
        </:rail>
      </OpsComponents.context_panel>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    section_atom = String.to_existing_atom(section)

    collapsed_sections =
      if MapSet.member?(socket.assigns.collapsed_sections, section_atom) do
        MapSet.delete(socket.assigns.collapsed_sections, section_atom)
      else
        MapSet.put(socket.assigns.collapsed_sections, section_atom)
      end

    {:noreply, assign(socket, :collapsed_sections, collapsed_sections)}
  end
end
