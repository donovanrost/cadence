defmodule CadenceWeb.CommsValidationLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.CommsValidation

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    findings = CommsValidation.findings_for_mission(scope, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Validation")
     |> assign(:nav_item, :comms_validation)
     |> assign(:findings, findings)
     |> assign(:finding_groups, CommsValidation.finding_groups(findings))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div id="comms-validation-page" class="space-y-6">
      <.page_header
        title="Validation"
        subtitle="Actionable checks for saved Spacecraft, Transport, Routing, and advanced runtime compatibility setup."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Validation", nil}
        ]}
      >
        <:title_suffix>{length(@findings)} findings</:title_suffix>
        <:actions>
          <.status_badge
            status={if @findings == [], do: :ready, else: :attention}
            label={if @findings == [], do: "No findings", else: "#{length(@findings)} findings"}
          />
        </:actions>
      </.page_header>

      <%= if @findings == [] do %>
        <.card id="comms-validation-empty">
          <.empty_state
            title="No setup findings"
            description="The saved mission-management configuration looks consistent."
          />
        </.card>
      <% else %>
        <div id="comms-validation-findings" class="space-y-5">
          <.card
            :for={group <- @finding_groups}
            id={group.id}
            heading={group.title}
            subtitle={group.description}
            padding={:none}
          >
            <div class="divide-y divide-base-300">
              <.finding_row :for={finding <- group.findings} finding={finding} />
            </div>
          </.card>
        </div>
      <% end %>
    </div>
    </Layouts.app>
    """
  end

  attr :finding, :map, required: true

  defp finding_row(assigns) do
    ~H"""
    <div id={Map.get(@finding, :id)} class="px-4 py-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h3 class="font-semibold">{@finding.title}</h3>
          <p class="mt-1 text-sm text-base-content/70">{@finding.body}</p>
          <.button
            :if={Map.get(@finding, :action_navigate)}
            size={:xs}
            navigate={@finding.action_navigate}
            class="mt-3"
          >
            {Map.get(@finding, :action_label, "Review")}
          </.button>
        </div>
        <.status_badge
          status={@finding.severity}
          label={CommsValidation.finding_label(@finding.severity)}
        />
      </div>
    </div>
    """
  end
end
