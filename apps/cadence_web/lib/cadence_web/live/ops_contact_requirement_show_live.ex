defmodule CadenceWeb.OpsContactRequirementShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{ContactRequirements, Planner}

  @impl true
  def mount(%{"contact_requirement_id" => requirement_id}, _session, socket) do
    socket =
      socket
      |> stream_configure(:requirement_versions,
        dom_id: &"requirement-version-#{&1.contact_requirement_version_id}"
      )
      |> stream_configure(:planning_searches,
        dom_id: &"planning-search-#{&1.contact_planning_search_id}"
      )
      |> stream_configure(:opportunities,
        dom_id: &"planning-opportunity-#{&1.contact_opportunity_snapshot_id}"
      )
      |> assign(:page_title, "Contact Requirement")
      |> assign(:ops_nav_item, :requirements)
      |> assign(:contact_requirement_id, requirement_id)
      |> assign(:planning?, false)
      |> assign(:planning_error, nil)
      |> assign(:selected_snapshot_ids, MapSet.new())

    case load_requirement(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, _reason} -> {:ok, push_navigate(socket, to: requirements_path(socket))}
    end
  end

  @impl true
  def handle_event("plan", _params, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    requirement = socket.assigns.requirement

    {:noreply,
     socket
     |> assign(:planning?, true)
     |> assign(:planning_error, nil)
     |> start_async(:plan_contact_requirement, fn ->
       Cadence.plan_contact_requirement(
         scope,
         mission.mission_id,
         requirement.contact_requirement_id,
         requirement.current_version
       )
     end)}
  end

  def handle_event("toggle-opportunity", %{"snapshot_id" => snapshot_id}, socket) do
    selected = socket.assigns.selected_snapshot_ids

    selected =
      if MapSet.member?(selected, snapshot_id),
        do: MapSet.delete(selected, snapshot_id),
        else: MapSet.put(selected, snapshot_id)

    {:noreply,
     socket
     |> assign(:selected_snapshot_ids, selected)
     |> stream(:opportunities, socket.assigns.opportunities, reset: true)}
  end

  def handle_event("create-plan", _params, socket) do
    selected = socket.assigns.selected_snapshot_ids

    snapshots =
      Enum.filter(socket.assigns.opportunities, fn snapshot ->
        MapSet.member?(selected, snapshot.contact_opportunity_snapshot_id)
      end)

    run_ids = snapshots |> Enum.map(& &1.contact_planning_run_id) |> Enum.uniq()
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.create_contact_plan(scope, mission.mission_id, %{
           planning_run_ids: run_ids,
           selected_snapshot_ids: Enum.map(snapshots, & &1.contact_opportunity_snapshot_id),
           rationale:
             "Operator-selected provider windows for #{socket.assigns.version.contact_intent}"
         }) do
      {:ok, plan, _version} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, plan_error(reason))}
    end
  end

  @impl true
  def handle_async(:plan_contact_requirement, {:ok, {:ok, _result}}, socket) do
    case load_requirement(assign(socket, :planning?, false)) do
      {:ok, socket} -> {:noreply, socket}
      {:error, reason} -> {:noreply, assign(socket, :planning_error, plan_error(reason))}
    end
  end

  def handle_async(:plan_contact_requirement, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:planning?, false)
     |> assign(:planning_error, plan_error(reason))}
  end

  def handle_async(:plan_contact_requirement, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:planning?, false)
     |> assign(
       :planning_error,
       "The planning worker stopped before provider evidence was complete."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-contact-requirement-show-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto max-w-[96rem]">
            <.link navigate={requirements_path(@current_mission.mission_id)} class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary">
              <.icon name="hero-arrow-left" class="h-3.5 w-3.5" /> Requirements
            </.link>
            <div class="mt-4 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
              <div>
                <div class="flex items-center gap-2">
                  <span class="border border-primary/30 bg-primary/5 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-primary">
                    {@version.priority}
                  </span>
                  <span class="font-mono text-[0.65rem] text-base-content/45">
                    Requirement v{@requirement.current_version}
                  </span>
                </div>
                <h1 class="mt-2 text-2xl font-bold tracking-tight">{intent_label(@version.contact_intent)}</h1>
                <p class="mt-2 max-w-3xl text-sm text-base-content/60">{outcome_sentence(@version)}</p>
              </div>
              <button
                id="plan-contact-requirement"
                type="button"
                phx-click="plan"
                disabled={@planning? or @requirement.lifecycle_state != :active}
                class="btn btn-primary btn-sm min-w-40 font-mono text-xs uppercase tracking-wider"
              >
                <%= if @planning? do %>
                  Querying providers
                <% else %>
                  Find options
                <% end %>
              </button>
            </div>
          </div>
        </header>

        <div class="mx-auto grid max-w-[96rem] gap-5 p-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(20rem,0.65fr)] lg:p-7">
          <div class="min-w-0 space-y-5">
            <section id="requirement-horizon" class="border border-base-300 bg-base-200/20">
              <div class="grid gap-4 p-4 sm:grid-cols-3">
                <div>
                  <p class="hud-label">Earliest acceptable</p>
                  <p class="mt-1 font-mono text-sm tabular-nums">{format_time(@version.earliest_start)}</p>
                </div>
                <div>
                  <p class="hud-label">Latest acceptable</p>
                  <p class="mt-1 font-mono text-sm tabular-nums">{format_time(@version.latest_end)}</p>
                </div>
                <div>
                  <p class="hud-label">Spacecraft</p>
                  <p class="mt-1 truncate font-mono text-sm">{@version.spacecraft_id}</p>
                </div>
              </div>
              <div class="border-t border-base-300 px-4 py-3 text-sm text-base-content/60">
                {@version.rationale}
              </div>
            </section>

            <section class="border border-base-300 bg-base-200/20">
              <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
                <div>
                  <p class="hud-label">Provider search evidence</p>
                  <p class="mt-1 text-sm text-base-content/55">
                    No availability and a failed search remain separate operational facts.
                  </p>
                </div>
                <span id="planning-run-state" class="font-mono text-xs text-base-content/60">
                  {if @latest_run, do: humanize(@latest_run.lifecycle_state), else: "not run"}
                </span>
              </div>
              <p :if={@planning_error} id="contact-planning-error" class="border-b border-error/30 bg-error/5 px-4 py-3 text-sm text-error">
                {@planning_error}
              </p>
              <div id="planning-searches" phx-update="stream">
                <div id="planning-searches-empty" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">
                  Run planning to query every provider-ready route.
                </div>
                <div :for={{dom_id, search} <- @streams.planning_searches} id={dom_id} class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3 last:border-b-0">
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold">{search.provider_display_name || readiness_label(search)}</p>
                    <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/45">{search.route_key}</p>
                    <p
                      id={"planning-search-evidence-#{search.contact_planning_search_id}"}
                      class="mt-1 text-xs text-base-content/55"
                    >
                      {search_evidence_summary(search)}
                    </p>
                  </div>
                  <div class="text-right">
                    <span class={search_state_class(search.outcome)}>{humanize(search.outcome)}</span>
                    <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">{search.opportunity_count} options</p>
                  </div>
                </div>
              </div>
            </section>

            <section class="border border-base-300 bg-base-200/20">
              <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
                <div>
                  <p class="hud-label">Opportunity comparison</p>
                  <p class="mt-1 text-sm text-base-content/55">Choose exact immutable snapshots for a draft Plan.</p>
                </div>
                <span id="selected-opportunity-count" class="font-mono text-sm text-primary">{MapSet.size(@selected_snapshot_ids)} selected</span>
              </div>
              <div id="planning-opportunities" phx-update="stream">
                <div id="planning-opportunities-empty" class="hidden only:block px-4 py-12 text-center text-sm text-base-content/50">
                  No provider opportunities were captured in the latest run.
                </div>
                <div
                  :for={{dom_id, snapshot} <- @streams.opportunities}
                  id={dom_id}
                  class={[
                    "grid gap-3 border-b border-base-300 px-4 py-4 last:border-b-0 md:grid-cols-[auto_minmax(0,1.2fr)_repeat(3,minmax(7rem,0.55fr))] md:items-center",
                    MapSet.member?(@selected_snapshot_ids, snapshot.contact_opportunity_snapshot_id) && "bg-primary/[0.06]"
                  ]}
                >
                  <button
                    id={"toggle-#{snapshot.contact_opportunity_snapshot_id}"}
                    type="button"
                    phx-click="toggle-opportunity"
                    phx-value-snapshot_id={snapshot.contact_opportunity_snapshot_id}
                    disabled={not snapshot.eligible}
                    aria-label="Toggle opportunity selection"
                    class={[
                      "h-5 w-5 border text-center font-mono text-xs",
                      MapSet.member?(@selected_snapshot_ids, snapshot.contact_opportunity_snapshot_id) && "border-primary bg-primary text-primary-content",
                      not MapSet.member?(@selected_snapshot_ids, snapshot.contact_opportunity_snapshot_id) && "border-base-content/30",
                      not snapshot.eligible && "cursor-not-allowed opacity-30"
                    ]}
                  >
                    {if MapSet.member?(@selected_snapshot_ids, snapshot.contact_opportunity_snapshot_id), do: "✓", else: ""}
                  </button>
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold">{snapshot.route_binding_document["provider_display_name"]}</p>
                    <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/45">{snapshot.normalized_opportunity_document["ground_station_ref"]}</p>
                  </div>
                  <div>
                    <p class="hud-label">UTC window</p>
                    <p class="mt-1 font-mono text-xs">{format_time(snapshot.starts_at)}</p>
                  </div>
                  <div>
                    <p class="hud-label">Duration</p>
                    <p class="mt-1 font-mono text-xs">{DateTime.diff(snapshot.ends_at, snapshot.starts_at)} sec</p>
                  </div>
                  <div>
                    <p class="hud-label">Eligibility</p>
                    <p class={if snapshot.eligible, do: "mt-1 text-xs text-success", else: "mt-1 text-xs text-error"}>
                      {eligibility_label(snapshot)}
                    </p>
                  </div>
                </div>
              </div>
              <div class="flex items-center justify-between gap-4 border-t border-base-300 bg-base-200/50 px-4 py-3">
                <p class="text-xs text-base-content/50">A draft records every considered option, including rejected alternatives.</p>
                <button
                  id="create-contact-plan"
                  type="button"
                  phx-click="create-plan"
                  disabled={MapSet.size(@selected_snapshot_ids) == 0}
                  class="btn btn-primary btn-sm font-mono text-xs uppercase tracking-wider"
                >
                  Build draft Plan
                </button>
              </div>
            </section>
          </div>

          <aside class="min-w-0 space-y-5">
            <section class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Need → Options → Plan → Reserved</p>
              </div>
              <div class="space-y-3 p-4 text-sm">
                <.status_line label="Need" state="Declared" complete />
                <.status_line label="Options" state={if @latest_run, do: humanize(@latest_run.lifecycle_state), else: "Pending"} complete={not is_nil(@latest_run)} />
                <.status_line label="Plan" state={plan_state(@plans)} complete={@plans != []} />
                <.status_line label="Reserved" state={reservation_state(@plans)} complete={reserved?(@plans)} />
              </div>
            </section>

            <section class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Immutable versions</p>
              </div>
              <div id="requirement-versions" phx-update="stream">
                <div :for={{dom_id, version} <- @streams.requirement_versions} id={dom_id} class="border-b border-base-300 px-4 py-3 last:border-b-0">
                  <div class="flex items-center justify-between">
                    <span class="font-mono text-xs text-primary">v{version.version}</span>
                    <span class="font-mono text-[0.65rem] text-base-content/45">{format_time(version.created_at)}</span>
                  </div>
                  <p class="mt-2 text-xs text-base-content/55">{version.rationale}</p>
                  <p class="mt-2 truncate font-mono text-[0.6rem] text-base-content/35">{version.content_sha256}</p>
                </div>
              </div>
            </section>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :state, :string, required: true
  attr :complete, :boolean, default: false

  defp status_line(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class={[
        "flex h-5 w-5 items-center justify-center border font-mono text-[0.6rem]",
        @complete && "border-success/50 bg-success/10 text-success",
        not @complete && "border-base-300 text-base-content/30"
      ]}>{if @complete, do: "✓", else: "·"}</span>
      <span class="flex-1 text-base-content/60">{@label}</span>
      <span class="font-mono text-xs">{@state}</span>
    </div>
    """
  end

  defp load_requirement(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    requirement_id = socket.assigns.contact_requirement_id

    with {:ok, requirement, version} <-
           Cadence.fetch_contact_requirement(
             scope.organization_id,
             mission.mission_id,
             requirement_id
           ) do
      versions =
        ContactRequirements.list_versions(
          scope.organization_id,
          mission.mission_id,
          requirement_id
        )

      runs = Planner.list_runs(scope.organization_id, mission.mission_id, requirement_id)
      latest_run = List.first(runs)

      {searches, opportunities} =
        if latest_run do
          {
            Planner.list_searches(
              scope.organization_id,
              mission.mission_id,
              latest_run.contact_planning_run_id
            ),
            Planner.list_snapshots(
              scope.organization_id,
              mission.mission_id,
              latest_run.contact_planning_run_id
            )
          }
        else
          {[], []}
        end

      opportunity_ids = MapSet.new(opportunities, & &1.contact_opportunity_snapshot_id)

      selected =
        socket.assigns.selected_snapshot_ids
        |> MapSet.intersection(opportunity_ids)

      plans =
        Cadence.list_contact_plans(scope.organization_id, mission.mission_id)
        |> Enum.filter(fn {_plan, plan_version} ->
          Enum.any?(
            plan_version.requirement_refs_document["requirements"] || [],
            &(&1["id"] == requirement_id)
          )
        end)

      {:ok,
       socket
       |> assign(:requirement, requirement)
       |> assign(:version, version)
       |> assign(:latest_run, latest_run)
       |> assign(:opportunities, opportunities)
       |> assign(:selected_snapshot_ids, selected)
       |> assign(:plans, plans)
       |> stream(:requirement_versions, versions, reset: true)
       |> stream(:planning_searches, searches, reset: true)
       |> stream(:opportunities, opportunities, reset: true)}
    end
  end

  defp requirements_path(%Phoenix.LiveView.Socket{} = socket),
    do: requirements_path(socket.assigns.current_mission.mission_id)

  defp requirements_path(mission_id), do: ~p"/missions/#{mission_id}/ops/requirements"

  defp outcome_sentence(%{success_measure: :minimum_data_volume} = version),
    do:
      "Downlink at least #{version.minimum_data_volume_bytes} bytes across #{version.contact_count} eligible contact(s)."

  defp outcome_sentence(%{success_measure: :minimum_duration} = version),
    do: "Secure at least #{version.minimum_duration_seconds} seconds of contact time."

  defp outcome_sentence(%{success_measure: :contact_count} = version),
    do: "Secure #{version.contact_count} eligible contact window(s)."

  defp outcome_sentence(_version), do: "Any eligible provider contact satisfies this need."

  defp eligibility_label(%{eligible: true}), do: "Eligible"

  defp eligibility_label(snapshot) do
    snapshot.evaluation_document["hard_failures"]
    |> List.first()
    |> case do
      nil -> "Ineligible"
      failure -> humanize(failure["code"])
    end
  end

  defp readiness_label(search), do: search.readiness_document["message"] || "Route readiness"

  defp search_evidence_summary(search) do
    case search.readiness_document["orbit_readiness"] do
      %{"status" => status} = readiness ->
        orbit_summary(status, readiness)

      [%{"status" => status} = readiness | _rest] ->
        orbit_summary(status, readiness)

      _other ->
        search_outcome_summary(search)
    end
  end

  defp orbit_summary(status, readiness) do
    reference = readiness["ephemeris_ref"]
    valid_until = readiness["valid_until"]

    [
      "Provider orbit data #{humanize(status)}",
      if(reference, do: "reference #{reference}"),
      if(valid_until, do: "valid through #{format_evidence_time(valid_until)}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp search_outcome_summary(%{outcome: :succeeded_without_results}),
    do: "Provider evaluated this horizon and returned no matching availability."

  defp search_outcome_summary(%{outcome: :failed, error_document: error}),
    do: "Provider search failed: #{humanize(error["code"] || "provider_search_failed")}."

  defp search_outcome_summary(%{outcome: :not_ready}),
    do: "Provider or route readiness prevented opportunity evaluation."

  defp search_outcome_summary(%{outcome: :excluded_by_requirement}),
    do: "Requirement constraints excluded this route before provider search."

  defp search_outcome_summary(_search), do: "Provider search completed with durable evidence."

  defp format_evidence_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_time(datetime)
      _error -> value
    end
  end

  defp format_evidence_time(value), do: to_string(value)

  defp search_state_class(outcome)
       when outcome in [:succeeded_with_results, :succeeded_without_results],
       do: "font-mono text-[0.65rem] uppercase text-success"

  defp search_state_class(:excluded_by_requirement),
    do: "font-mono text-[0.65rem] uppercase text-base-content/45"

  defp search_state_class(_outcome), do: "font-mono text-[0.65rem] uppercase text-warning"

  defp plan_state([]), do: "Pending"
  defp plan_state([{plan, _version} | _rest]), do: humanize(plan.lifecycle_state)

  defp reservation_state(plans) do
    if reserved?(plans), do: "Capacity held", else: "Pending"
  end

  defp reserved?(plans),
    do:
      Enum.any?(plans, fn {plan, _version} ->
        plan.lifecycle_state in [:reserved, :partially_reserved]
      end)

  defp plan_error(:contact_planning_route_resolution_malformed),
    do: "Cadence could not resolve provider routes."

  defp plan_error(:contact_requirement_direction_not_executable),
    do: "Only downlink Requirements can be planned in this stage."

  defp plan_error({:contact_planning_route_resolution_failed, _detail}),
    do: "Provider route resolution failed. Review Comms readiness."

  defp plan_error(_reason), do: "Planning could not complete. Existing evidence was preserved."
  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %Y %H:%MZ")
  defp intent_label(intent), do: intent |> String.replace("_", " ") |> String.capitalize()
  defp humanize(item), do: item |> to_string() |> String.replace("_", " ")
end
