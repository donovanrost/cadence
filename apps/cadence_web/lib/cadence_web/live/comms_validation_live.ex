defmodule CadenceWeb.CommsValidationLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.CommsValidation

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    findings = CommsValidation.findings_for_mission(scope.organization_id, mission.mission_id)

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
    <div id="comms-validation-page" class="space-y-6">
      <div class="flex items-start justify-between gap-4 border-b border-primary/20 pb-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms"}
            class="hud-label text-base-content/50 hover:text-primary"
          >
            &larr; Comms
          </.link>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            Validation
            <span class="ml-3 font-mono text-base text-base-content/40">
              {length(@findings)} findings
            </span>
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            Actionable checks for saved Spacecraft, Transport, Routing, and advanced runtime compatibility setup.
          </p>
        </div>
        <.status_badge
          status={if @findings == [], do: :ready, else: :attention}
          label={if @findings == [], do: "No findings", else: "#{length(@findings)} findings"}
        />
      </div>

      <%= if @findings == [] do %>
        <div id="comms-validation-empty" class="card bg-base-200 hud-corners border border-base-300">
          <div class="card-body p-8 text-center">
            <p class="hud-label mb-3 text-success">No setup findings</p>
            <p class="mx-auto max-w-md text-sm text-base-content/60">
              The saved mission-management configuration looks consistent.
            </p>
          </div>
        </div>
      <% else %>
        <div id="comms-validation-findings" class="space-y-5">
          <section :for={group <- @finding_groups} id={group.id} class="card bg-base-200 hud-corners border border-base-300">
            <div class="card-body p-0">
              <div class="border-b border-base-300 px-4 py-3">
                <h2 class="text-base font-semibold text-base-content">{group.title}</h2>
                <p class="mt-1 text-sm text-base-content/60">{group.description}</p>
              </div>

              <div class="divide-y divide-base-300">
                <div :for={finding <- group.findings} class="px-4 py-4">
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <h3 class="font-semibold">{finding.title}</h3>
                      <p class="mt-1 text-sm text-base-content/60">{finding.body}</p>
                      <.link
                        :if={Map.get(finding, :action_navigate)}
                        navigate={finding.action_navigate}
                        class="btn btn-primary btn-xs mt-3"
                      >
                        {Map.get(finding, :action_label, "Review")}
                      </.link>
                    </div>
                    <.status_badge
                      status={finding.severity}
                      label={CommsValidation.finding_label(finding.severity)}
                    />
                  </div>
                </div>
              </div>
            </div>
          </section>
        </div>
      <% end %>
    </div>
    """
  end
end
