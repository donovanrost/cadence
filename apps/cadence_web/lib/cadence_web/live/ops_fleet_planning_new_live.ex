defmodule CadenceWeb.OpsFleetPlanningNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    policy =
      case Cadence.fetch_active_fleet_planning_policy(
             socket.assigns.current_scope.organization_id,
             socket.assigns.current_mission.mission_id
           ) do
        {:ok, resource, version} -> {resource, version}
        {:error, _reason} -> nil
      end

    form =
      to_form(
        %{
          "horizon_start" => datetime_local(now),
          "horizon_end" => datetime_local(DateTime.add(now, 12, :hour)),
          "include_recurring" => "true"
        },
        as: :fleet_run
      )

    {:ok,
     socket
     |> assign(:page_title, "Plan Fleet Horizon")
     |> assign(:ops_nav_item, :planning)
     |> assign(:active_policy, policy)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate-fleet-run", %{"fleet_run" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :fleet_run))}
  end

  def handle_event("create-fleet-run", %{"fleet_run" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, horizon_start} <- parse_datetime(params["horizon_start"]),
         {:ok, horizon_end} <- parse_datetime(params["horizon_end"]),
         {:ok, run, _refs} <-
           Cadence.start_fleet_planning_run(
             scope,
             mission.mission_id,
             %{
               horizon_start: horizon_start,
               horizon_end: horizon_end,
               trigger_kind: :manual
             },
             materialize_templates: truthy?(params["include_recurring"])
           ) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
       )}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-fleet-planning-new-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto max-w-5xl">
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning"}
              class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
            >
              <.icon name="hero-arrow-left" class="h-3.5 w-3.5" /> Fleet planning
            </.link>
            <h1 class="mt-4 text-2xl font-bold tracking-tight">Plan a mission horizon</h1>
            <p class="mt-2 max-w-3xl text-sm text-base-content/60">
              Choose only the time boundary. The active policy supplies concurrency, resource, quota, budget, scoring, repair, and automation rules.
            </p>
          </div>
        </header>

        <div class="mx-auto grid max-w-5xl gap-5 p-5 lg:grid-cols-[minmax(0,1fr)_20rem] lg:p-7">
          <section class="border border-base-300 bg-base-200/15 p-5">
            <%= if @active_policy do %>
              <.form
                for={@form}
                id="fleet-planning-run-form"
                phx-change="validate-fleet-run"
                phx-submit="create-fleet-run"
                class="space-y-5"
              >
                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    id="fleet-run-horizon-start"
                    field={@form[:horizon_start]}
                    type="datetime-local"
                    label="Horizon starts (UTC)"
                    required
                  />
                  <.input
                    id="fleet-run-horizon-end"
                    field={@form[:horizon_end]}
                    type="datetime-local"
                    label="Horizon ends (UTC)"
                    required
                  />
                </div>

                <.input
                  id="fleet-run-include-recurring"
                  field={@form[:include_recurring]}
                  type="checkbox"
                  label="Materialize recurring Requirement Templates in this horizon"
                />

                <div class="border-l-2 border-primary/35 bg-primary/[0.035] px-4 py-3">
                  <p class="hud-label">Snapshot boundary</p>
                  <p class="mt-1 text-sm text-base-content/60">
                    Starting the run freezes exact Requirement and policy versions. Later edits stop the run closed rather than silently changing its inputs.
                  </p>
                </div>

                <button
                  id="start-fleet-planning-run"
                  type="submit"
                  class="btn btn-primary btn-sm w-full font-mono text-xs uppercase tracking-wider"
                >
                  Start durable planning run
                </button>
              </.form>
            <% else %>
              <div id="fleet-planning-new-policy-required" class="py-10 text-center">
                <.icon name="hero-lock-closed" class="mx-auto h-8 w-8 text-warning/60" />
                <h2 class="mt-4 text-base font-semibold">An approved policy is required</h2>
                <p class="mx-auto mt-2 max-w-lg text-sm text-base-content/55">
                  Provider searches remain stopped until an organization administrator approves the fleet boundary.
                </p>
                <.link
                  navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning/policy"}
                  class="btn btn-warning btn-sm mt-5"
                >
                  Open policy
                </.link>
              </div>
            <% end %>
          </section>

          <aside :if={@active_policy} id="fleet-run-policy-preview" class="border border-base-300 bg-base-200/15">
            <div class="border-b border-base-300 px-4 py-3">
              <p class="hud-label">Active policy</p>
              <p class="mt-1 font-mono text-sm">v{policy_version(@active_policy).version}</p>
            </div>
            <dl class="divide-y divide-base-300 text-xs">
              <.policy_fact
                term="Maximum horizon"
                value={"#{div(policy_version(@active_policy).horizon_document["max_horizon_seconds"], 3_600)} hours"}
              />
              <.policy_fact
                term="Requirement workers"
                value={policy_version(@active_policy).horizon_document["requirement_concurrency"]}
              />
              <.policy_fact
                term="Provider searches"
                value={policy_version(@active_policy).horizon_document["provider_search_concurrency"]}
              />
              <.policy_fact
                term="Contact ceiling"
                value={policy_version(@active_policy).budget_quota_document["max_contacts"] || "none"}
              />
              <.policy_fact
                term="Automation"
                value={humanize(policy_version(@active_policy).automation_repair_document["mode"])}
              />
            </dl>
            <details id="fleet-run-policy-progressive-details" class="border-t border-base-300">
              <summary class="cursor-pointer px-4 py-3 text-xs font-semibold">
                Why these settings?
              </summary>
              <p class="border-t border-base-300 px-4 py-3 text-xs leading-relaxed text-base-content/55">
                Operators choose demand and horizon. Administrators own organizational risk: provider concurrency, cost, quotas, and unattended authority.
              </p>
            </details>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :term, :string, required: true
  attr :value, :any, required: true

  defp policy_fact(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 px-4 py-3">
      <dt class="text-base-content/50">{@term}</dt>
      <dd class="font-mono text-base-content/75">{@value}</dd>
    </div>
    """
  end

  defp policy_version({_policy, version}), do: version

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      {:error, _reason} -> {:error, :fleet_planning_horizon_invalid}
    end
  end

  defp parse_datetime(_value), do: {:error, :fleet_planning_horizon_invalid}

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp action_error(:fleet_planning_run_has_no_requirements),
    do: "No active Contact Requirements overlap this horizon."

  defp action_error(:active_fleet_planning_policy_not_found),
    do: "Approve a fleet planning policy before starting a run."

  defp action_error(:fleet_planning_horizon_exceeds_policy),
    do: "The requested horizon exceeds the active policy boundary."

  defp action_error(_reason), do: "The fleet planning run could not be started."
end
