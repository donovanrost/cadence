defmodule CadenceWeb.OpsContactRequirementListLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.Planner

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    requirements = Cadence.list_contact_requirements(scope.organization_id, mission.mission_id)
    plans = Cadence.list_contact_plans(scope.organization_id, mission.mission_id)

    rows =
      Enum.map(requirements, fn {requirement, version} ->
        runs =
          Planner.list_runs(
            scope.organization_id,
            mission.mission_id,
            requirement.contact_requirement_id
          )

        plan = plan_for_requirement(plans, requirement.contact_requirement_id)

        %{
          id: requirement.contact_requirement_id,
          requirement: requirement,
          version: version,
          latest_run: List.first(runs),
          plan: plan
        }
      end)

    {:ok,
     socket
     |> assign(:page_title, "Contact Requirements")
     |> assign(:ops_nav_item, :requirements)
     |> assign(:requirement_count, length(rows))
     |> assign(:requirement_empty?, rows == [])
     |> stream_configure(:requirements, dom_id: &"contact-requirement-#{&1.id}")
     |> stream(:requirements, rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-contact-requirements-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-[96rem] flex-col gap-5 md:flex-row md:items-end md:justify-between">
            <div>
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
                Mission operations / planning horizon
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">Contact Requirements</h1>
              <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                Declare the mission outcome first. Cadence searches every ready provider route, preserves their evidence, and lets operators commit an exact plan.
              </p>
            </div>
            <.link
              id="new-contact-requirement-link"
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/requirements/new"}
              class="btn btn-primary btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
            >
              <.icon name="hero-plus" class="h-4 w-4" /> Declare need
            </.link>
          </div>
        </header>

        <div class="mx-auto max-w-[96rem] p-5 lg:p-7">
          <div class="mb-5 grid border border-base-300 bg-base-200/25 sm:grid-cols-4">
            <.journey_step number="01" label="Need" detail="Mission outcome" active />
            <.journey_step number="02" label="Options" detail="Provider evidence" />
            <.journey_step number="03" label="Plan" detail="Exact commitment" />
            <.journey_step number="04" label="Reserved" detail="Provider capacity" />
          </div>

          <div
            :if={@requirement_empty?}
            id="contact-requirements-empty"
            class="border border-dashed border-base-300 bg-base-200/20 px-6 py-16 text-center"
          >
            <.icon name="hero-clipboard-document-list" class="mx-auto h-8 w-8 text-primary/40" />
            <h2 class="mt-4 text-lg font-semibold">No contact needs in this horizon</h2>
            <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/60">
              Start with the outcome the spacecraft needs—data volume, duration, or contact count. Provider details come later.
            </p>
          </div>

          <div id="contact-requirements" phx-update="stream" class="space-y-3">
            <div id="contact-requirements-stream-empty" class="hidden only:block"></div>
            <.link
              :for={{dom_id, row} <- @streams.requirements}
              id={dom_id}
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/requirements/#{row.requirement.contact_requirement_id}"}
              class="group block border border-base-300 bg-base-200/20 transition-colors hover:border-primary/50 hover:bg-primary/[0.03]"
            >
              <div class="grid gap-4 px-4 py-4 md:grid-cols-[minmax(0,1.4fr)_minmax(15rem,0.8fr)_auto] md:items-center">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class={priority_class(row.version.priority)}>
                      {row.version.priority}
                    </span>
                    <span class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
                      v{row.version.version} · {row.version.service_direction}
                    </span>
                  </div>
                  <h2 class="mt-2 truncate text-base font-semibold group-hover:text-primary">
                    {intent_label(row.version.contact_intent)}
                  </h2>
                  <p class="mt-1 truncate text-sm text-base-content/55">
                    {outcome_sentence(row.version)}
                  </p>
                </div>
                <div>
                  <p class="hud-label">Acceptable UTC window</p>
                  <p class="mt-1 font-mono text-xs tabular-nums text-base-content/75">
                    {short_time(row.version.earliest_start)} → {short_time(row.version.latest_end)}
                  </p>
                  <div class="mt-2 h-1.5 overflow-hidden bg-base-300">
                    <div class="h-full w-2/3 bg-primary/65"></div>
                  </div>
                </div>
                <div class="min-w-36 border-l border-base-300 pl-4">
                  <p class="hud-label">Journey state</p>
                  <p class="mt-1 text-sm font-semibold text-base-content/80">
                    {journey_state(row)}
                  </p>
                  <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">
                    {journey_detail(row)}
                  </p>
                </div>
              </div>
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :number, :string, required: true
  attr :label, :string, required: true
  attr :detail, :string, required: true
  attr :active, :boolean, default: false

  defp journey_step(assigns) do
    ~H"""
    <div class={[
      "border-b border-base-300 px-4 py-3 sm:border-b-0 sm:border-r last:border-r-0",
      @active && "bg-primary/[0.06]"
    ]}>
      <p class="font-mono text-[0.6rem] tracking-[0.2em] text-primary/60">{@number}</p>
      <p class="mt-1 text-sm font-semibold">{@label}</p>
      <p class="mt-0.5 text-xs text-base-content/45">{@detail}</p>
    </div>
    """
  end

  defp plan_for_requirement(plans, requirement_id) do
    Enum.find_value(plans, fn {plan, version} ->
      if Enum.any?(
           version.requirement_refs_document["requirements"] || [],
           &(&1["id"] == requirement_id)
         ),
         do: plan,
         else: nil
    end)
  end

  defp journey_state(%{plan: %{lifecycle_state: state}})
       when state in [:reserved, :partially_reserved],
       do: "Reserved"

  defp journey_state(%{plan: %{lifecycle_state: state}})
       when state in [:draft, :pending_approval, :approved, :executing, :failed],
       do: "Plan #{humanize(state)}"

  defp journey_state(%{latest_run: nil}), do: "Need declared"
  defp journey_state(_row), do: "Options captured"

  defp journey_detail(%{plan: plan}), do: humanize(plan.lifecycle_state)
  defp journey_detail(%{latest_run: nil}), do: "Search not run"
  defp journey_detail(%{latest_run: run}), do: humanize(run.lifecycle_state)

  defp priority_class(:critical),
    do:
      "border border-error/40 bg-error/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-error"

  defp priority_class(:high),
    do:
      "border border-warning/40 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-warning"

  defp priority_class(_priority),
    do:
      "border border-base-300 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-base-content/55"

  defp outcome_sentence(%{success_measure: :minimum_data_volume} = version),
    do:
      "Deliver at least #{format_bytes(version.minimum_data_volume_bytes)} across #{version.contact_count} contact(s)."

  defp outcome_sentence(%{success_measure: :minimum_duration} = version),
    do: "Secure at least #{version.minimum_duration_seconds} seconds of contact time."

  defp outcome_sentence(%{success_measure: :contact_count} = version),
    do: "Secure #{version.contact_count} separated contact window(s)."

  defp outcome_sentence(_version), do: "Any eligible contact satisfies this need."

  defp format_bytes(bytes) when bytes >= 1_000_000_000,
    do: "#{Float.round(bytes / 1_000_000_000, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp format_bytes(bytes), do: "#{bytes} bytes"
  defp short_time(datetime), do: Calendar.strftime(datetime, "%d %b %H:%MZ")
  defp intent_label(intent), do: intent |> String.replace("_", " ") |> String.capitalize()
  defp humanize(item), do: item |> to_string() |> String.replace("_", " ")
end
