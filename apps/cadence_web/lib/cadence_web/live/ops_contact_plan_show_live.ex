defmodule CadenceWeb.OpsContactPlanShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{
    ContactPlanApprovals,
    ContactPlanExecutions,
    ContactPlans,
    ContactRequirements
  }

  @impl true
  def mount(%{"contact_plan_id" => plan_id}, _session, socket) do
    socket =
      socket
      |> stream_configure(:selected_opportunities,
        dom_id: &"plan-selection-#{&1.contact_opportunity_snapshot_id}"
      )
      |> stream_configure(:execution_items,
        dom_id: &"plan-execution-item-#{&1.contact_plan_execution_item_id}"
      )
      |> stream_configure(:approvals,
        dom_id: &"plan-approval-#{&1.contact_plan_approval_id}"
      )
      |> assign(:page_title, "Contact Plan")
      |> assign(:ops_nav_item, :requirements)
      |> assign(:contact_plan_id, plan_id)
      |> assign(:executing?, false)
      |> assign(
        :submit_form,
        to_form(%{"reason" => "Ready for commitment review"}, as: :submission)
      )
      |> assign(:decision_form, to_form(%{"reason" => ""}, as: :decision))

    case load_plan(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, _reason} -> {:ok, push_navigate(socket, to: requirements_path(socket))}
    end
  end

  @impl true
  def handle_event("submit-plan", %{"submission" => %{"reason" => reason}}, socket) do
    %{current_scope: scope, current_mission: mission, plan: plan} = socket.assigns

    case ContactPlans.submit(
           scope,
           mission.mission_id,
           plan.contact_plan_id,
           plan.current_version,
           reason
         ) do
      {:ok, _plan} ->
        refresh_with_flash(socket, :info, "Plan submitted for administrator review.")

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_event("approve-plan", %{"decision" => %{"reason" => reason}}, socket) do
    decide(socket, :approve, reason)
  end

  def handle_event("reject-plan", %{"decision" => %{"reason" => reason}}, socket) do
    decide(socket, :reject, reason)
  end

  def handle_event("execute-plan", _params, socket) do
    %{current_scope: scope, current_mission: mission, plan: plan} = socket.assigns

    {:noreply,
     socket
     |> assign(:executing?, true)
     |> start_async(:execute_contact_plan, fn ->
       ContactPlanExecutions.execute(scope, mission.mission_id, plan.contact_plan_id)
     end)}
  end

  @impl true
  def handle_async(:execute_contact_plan, {:ok, {:ok, _result}}, socket) do
    case load_plan(assign(socket, :executing?, false)) do
      {:ok, socket} -> {:noreply, put_flash(socket, :info, "Plan execution projection updated.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_async(:execute_contact_plan, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:executing?, false)
     |> put_flash(:error, action_error(reason))}
  end

  def handle_async(:execute_contact_plan, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:executing?, false)
     |> put_flash(:error, "Execution worker stopped. Durable reservation evidence was preserved.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-contact-plan-show-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto max-w-[96rem]">
            <.link navigate={requirement_path(@current_mission.mission_id, @requirements)} class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary">
              <.icon name="hero-arrow-left" class="h-3.5 w-3.5" /> Requirement
            </.link>
            <div class="mt-4 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <span class={plan_state_class(@plan.lifecycle_state)}>{humanize(@plan.lifecycle_state)}</span>
                  <span class="font-mono text-[0.65rem] text-base-content/45">Plan v{@version.version}</span>
                </div>
                <h1 class="mt-2 text-2xl font-bold tracking-tight">Contact commitment manifest</h1>
                <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                  Exact Requirement, opportunity, provider route, policy, and expiry evidence for this commitment.
                </p>
              </div>
              <button
                :if={@plan.lifecycle_state in [:approved, :executing, :partially_reserved, :failed]}
                id="execute-contact-plan"
                type="button"
                phx-click="execute-plan"
                disabled={@executing?}
                class="btn btn-primary btn-sm min-w-40 font-mono text-xs uppercase tracking-wider"
              >
                {if @executing?, do: "Executing", else: "Execute approved Plan"}
              </button>
            </div>
          </div>
        </header>

        <div class="mx-auto grid max-w-[96rem] gap-5 p-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(21rem,0.7fr)] lg:p-7">
          <div class="min-w-0 space-y-5">
            <section id="plan-commitment-summary" class="border border-base-300 bg-base-200/20">
              <div class="grid gap-4 p-4 sm:grid-cols-3">
                <div>
                  <p class="hud-label">Requirement coverage</p>
                  <p class={[
                    "mt-1 text-sm font-semibold",
                    @version.coverage_document["satisfied"] && "text-success",
                    not @version.coverage_document["satisfied"] && "text-warning"
                  ]}>
                    {if @version.coverage_document["satisfied"], do: "Satisfied", else: "Shortfall recorded"}
                  </p>
                </div>
                <div>
                  <p class="hud-label">Selected windows</p>
                  <p class="mt-1 font-mono text-sm">{length(@selected_opportunities)}</p>
                </div>
                <div>
                  <p class="hud-label">Approval identity</p>
                  <p class="mt-1 font-mono text-sm">{approval_identity(@plan)}</p>
                </div>
              </div>
              <div class="border-t border-base-300 px-4 py-3">
                <p class="hud-label">Exact content hash</p>
                <p id="contact-plan-content-hash" class="mt-1 break-all font-mono text-[0.68rem] text-base-content/55">{@version.content_sha256}</p>
              </div>
            </section>

            <section class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Selected provider windows</p>
                <p class="mt-1 text-sm text-base-content/55">These immutable snapshots are the only opportunities execution may reserve.</p>
              </div>
              <div id="plan-selections" phx-update="stream">
                <div id="plan-selections-empty" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">No opportunities selected.</div>
                <div :for={{dom_id, snapshot} <- @streams.selected_opportunities} id={dom_id} class="grid gap-3 border-b border-base-300 px-4 py-4 last:border-b-0 md:grid-cols-[minmax(0,1.2fr)_repeat(3,minmax(8rem,0.55fr))] md:items-center">
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold">{snapshot.route_binding_document["provider_display_name"]}</p>
                    <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/45">{snapshot.normalized_opportunity_document["ground_station_ref"]}</p>
                  </div>
                  <div>
                    <p class="hud-label">Starts UTC</p>
                    <p class="mt-1 font-mono text-xs">{format_time(snapshot.starts_at)}</p>
                  </div>
                  <div>
                    <p class="hud-label">Duration</p>
                    <p class="mt-1 font-mono text-xs">{DateTime.diff(snapshot.ends_at, snapshot.starts_at)} sec</p>
                  </div>
                  <div>
                    <p class="hud-label">Opportunity expires</p>
                    <p class={expiry_class(snapshot.expires_at)}>{format_time(snapshot.expires_at)}</p>
                  </div>
                </div>
              </div>
            </section>

            <section :if={not @version.unsatisfied_document["clear"]} id="plan-unsatisfied" class="border border-warning/40 bg-warning/5">
              <div class="border-b border-warning/30 px-4 py-3">
                <p class="hud-label text-warning">Unsatisfied outcomes</p>
              </div>
              <div class="space-y-3 p-4">
                <div :for={item <- @version.unsatisfied_document["requirements"] || []} class="text-sm">
                  <p class="font-mono text-xs text-warning">{item["contact_requirement_id"]} v{item["contact_requirement_version"]}</p>
                  <p :for={failure <- item["hard_failures"] || []} class="mt-1 text-base-content/65">{humanize(failure["code"])}</p>
                </div>
              </div>
            </section>

            <details id="plan-policy-manifest" class="border border-base-300 bg-base-200/20">
              <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">Policy and route evidence</summary>
              <div class="border-t border-base-300 p-4">
                <div :for={selection <- @version.policy_snapshot_document["selections"] || []} class="mb-4 border-l-2 border-primary/30 pl-3 last:mb-0">
                  <p class="font-mono text-[0.65rem] text-base-content/45">{selection["contact_opportunity_snapshot_id"]}</p>
                  <p class="mt-1 text-sm">{selection["route_binding"]["route_display_name"]}</p>
                  <p class="mt-1 text-xs text-base-content/55">
                    Effective policy: {humanize(selection["effective_policy"]["mode"])} · automatic revision {if selection["effective_policy"]["allow_automatic_execution_revision"], do: "allowed", else: "disabled"}
                  </p>
                </div>
              </div>
            </details>

            <section class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Execution ledger</p>
                <p class="mt-1 text-sm text-base-content/55">One restart-safe saga item per selected opportunity.</p>
              </div>
              <div id="plan-execution-items" phx-update="stream">
                <div id="plan-execution-items-empty" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">Execution items are created only after approval.</div>
                <div :for={{dom_id, item} <- @streams.execution_items} id={dom_id} class="flex items-center justify-between gap-4 border-b border-base-300 px-4 py-3 last:border-b-0">
                  <div class="min-w-0">
                    <p class="truncate font-mono text-xs">{item.contact_opportunity_snapshot_id}</p>
                    <p class="mt-1 font-mono text-[0.6rem] text-base-content/40">attempts {item.attempt_count}</p>
                  </div>
                  <div class="flex items-center gap-3">
                    <span class={execution_state_class(item.lifecycle_state)}>{humanize(item.lifecycle_state)}</span>
                    <.link
                      :if={item.provider_reservation_id}
                      navigate={~p"/missions/#{@current_mission.mission_id}/ops/contacts/#{item.provider_reservation_id}"}
                      class="text-xs text-primary hover:underline"
                    >
                      Contact
                    </.link>
                  </div>
                </div>
              </div>
            </section>
          </div>

          <aside class="min-w-0 space-y-5">
            <section :if={@plan.lifecycle_state == :draft and @approvals == []} class="border border-base-300 bg-base-200/20 p-4">
              <p class="hud-label">Submit for approval</p>
              <p class="mt-2 text-sm text-base-content/55">Freeze this exact version for an organization administrator to review.</p>
              <.form for={@submit_form} id="contact-plan-submit-form" phx-submit="submit-plan" class="mt-4">
                <.input id="contact-plan-submit-reason" field={@submit_form[:reason]} type="textarea" label="Review note" required />
                <button id="submit-contact-plan" type="submit" class="btn btn-primary btn-sm w-full font-mono text-xs uppercase tracking-wider">Submit exact v{@version.version}</button>
              </.form>
            </section>

            <section :if={@plan.lifecycle_state == :pending_approval} class="border border-primary/35 bg-primary/[0.04] p-4">
              <p class="hud-label">Administrator decision</p>
              <p class="mt-2 text-sm text-base-content/55">
                Approval rechecks Requirement versions, expiry, route/grant readiness, and policy narrowing.
              </p>
              <%= if @organization_admin? do %>
                <.form
                  for={@decision_form}
                  id="contact-plan-approve-form"
                  phx-submit="approve-plan"
                  class="mt-4"
                >
                  <.input
                    id="contact-plan-approve-reason"
                    field={@decision_form[:reason]}
                    type="textarea"
                    label="Approval reason"
                    required
                  />
                  <button id="approve-contact-plan" type="submit" class="btn btn-primary btn-sm w-full">
                    Approve exact v{@version.version}
                  </button>
                </.form>
                <details id="contact-plan-rejection-disclosure" class="mt-3 border-t border-base-300 pt-3">
                  <summary class="cursor-pointer text-xs text-error">Reject this version</summary>
                  <.form
                    for={@decision_form}
                    id="contact-plan-reject-form"
                    phx-submit="reject-plan"
                    class="mt-3"
                  >
                    <.input
                      id="contact-plan-reject-reason"
                      field={@decision_form[:reason]}
                      type="textarea"
                      label="Rejection reason"
                      required
                    />
                    <button id="reject-contact-plan" type="submit" class="btn btn-ghost btn-sm w-full text-error">
                      Reject and require a new version
                    </button>
                  </.form>
                </details>
              <% else %>
                <p id="contact-plan-admin-required" class="mt-4 border-l-2 border-warning px-3 text-xs text-warning">Organization administrator approval required.</p>
              <% end %>
            </section>

            <section class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-4 py-3"><p class="hud-label">Approval evidence</p></div>
              <div id="plan-approvals" phx-update="stream">
                <div id="plan-approvals-empty" class="hidden only:block px-4 py-8 text-center text-sm text-base-content/50">No decision recorded.</div>
                <div :for={{dom_id, approval} <- @streams.approvals} id={dom_id} class="border-b border-base-300 p-4 last:border-b-0">
                  <div class="flex items-center justify-between">
                    <span class={if approval.decision == :approved, do: "text-sm font-semibold text-success", else: "text-sm font-semibold text-error"}>{humanize(approval.decision)}</span>
                    <span class="font-mono text-[0.65rem] text-base-content/45">v{approval.contact_plan_version}</span>
                  </div>
                  <p class="mt-2 text-sm text-base-content/60">{approval.reason}</p>
                  <p class="mt-2 font-mono text-[0.65rem] text-base-content/40">{approval.actor_document["display_name"]} · {format_time(approval.decided_at)}</p>
                </div>
              </div>
            </section>

            <section class="border border-base-300 bg-base-200/20 p-4">
              <p class="hud-label">Operator rationale</p>
              <p class="mt-2 text-sm text-base-content/60">{@version.rationale}</p>
              <p class="mt-3 font-mono text-[0.6rem] text-base-content/35">{@plan.contact_plan_id}</p>
            </section>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp decide(socket, decision, reason) do
    %{current_scope: scope, current_mission: mission, plan: plan, version: version} =
      socket.assigns

    result =
      case decision do
        :approve ->
          ContactPlanApprovals.approve(
            scope,
            mission.mission_id,
            plan.contact_plan_id,
            plan.current_version,
            version.content_sha256,
            reason
          )

        :reject ->
          ContactPlanApprovals.reject(
            scope,
            mission.mission_id,
            plan.contact_plan_id,
            plan.current_version,
            version.content_sha256,
            reason
          )
      end

    case result do
      {:ok, _plan, _version, _approval} ->
        refresh_with_flash(socket, :info, "Plan decision recorded.")

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  defp refresh_with_flash(socket, kind, message) do
    case load_plan(socket) do
      {:ok, socket} -> {:noreply, put_flash(socket, kind, message)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  defp load_plan(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    plan_id = socket.assigns.contact_plan_id

    with {:ok, plan, version} <-
           ContactPlans.fetch(scope.organization_id, mission.mission_id, plan_id) do
      requirements =
        Enum.map(version.requirement_refs_document["requirements"] || [], fn ref ->
          {:ok, requirement} =
            ContactRequirements.fetch_version(
              scope.organization_id,
              mission.mission_id,
              ref["id"],
              ref["version"]
            )

          requirement
        end)

      selected =
        ContactPlans.selected_snapshots(
          scope.organization_id,
          mission.mission_id,
          plan.contact_plan_id,
          version.version
        )

      approvals =
        ContactPlanApprovals.list(
          scope.organization_id,
          mission.mission_id,
          plan.contact_plan_id
        )

      execution_version = plan.approved_version || version.version

      execution_items =
        ContactPlanExecutions.list(
          scope.organization_id,
          mission.mission_id,
          plan.contact_plan_id,
          execution_version
        )

      {:ok,
       socket
       |> assign(:plan, plan)
       |> assign(:version, version)
       |> assign(:requirements, requirements)
       |> assign(:selected_opportunities, selected)
       |> assign(:approvals, approvals)
       |> assign(:organization_admin?, organization_admin?(scope))
       |> stream(:selected_opportunities, selected, reset: true)
       |> stream(:execution_items, execution_items, reset: true)
       |> stream(:approvals, approvals, reset: true)}
    end
  end

  defp requirement_path(mission_id, [requirement | _rest]),
    do: ~p"/missions/#{mission_id}/ops/requirements/#{requirement.contact_requirement_id}"

  defp requirement_path(mission_id, []), do: requirements_path(mission_id)

  defp requirements_path(%Phoenix.LiveView.Socket{} = socket),
    do: requirements_path(socket.assigns.current_mission.mission_id)

  defp requirements_path(mission_id), do: ~p"/missions/#{mission_id}/ops/requirements"

  defp organization_admin?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end

  defp approval_identity(%{approved_by: nil}), do: "Not approved"
  defp approval_identity(plan), do: plan.approved_by

  defp plan_state_class(:approved),
    do:
      "border border-primary/40 bg-primary/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-primary"

  defp plan_state_class(:reserved),
    do:
      "border border-success/40 bg-success/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-success"

  defp plan_state_class(:partially_reserved),
    do:
      "border border-warning/40 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-warning"

  defp plan_state_class(_state),
    do:
      "border border-base-300 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-base-content/60"

  defp execution_state_class(:reserved), do: "font-mono text-[0.65rem] uppercase text-success"

  defp execution_state_class(state) when state in [:uncertain, :failed, :rejected],
    do: "font-mono text-[0.65rem] uppercase text-warning"

  defp execution_state_class(_state), do: "font-mono text-[0.65rem] uppercase text-primary"

  defp expiry_class(expires_at) do
    if DateTime.after?(expires_at, DateTime.utc_now()),
      do: "mt-1 font-mono text-xs text-base-content/65",
      else: "mt-1 font-mono text-xs text-error"
  end

  defp action_error(:contact_plan_opportunity_expired),
    do: "A selected provider opportunity expired. Re-plan the Requirement."

  defp action_error(:contact_plan_route_not_ready),
    do: "An exact provider route or account grant is no longer ready."

  defp action_error(:contact_plan_requirement_changed),
    do: "The Requirement changed after this Plan was built. Create a new Plan."

  defp action_error(:contact_plan_not_satisfied),
    do: "This Plan does not satisfy its Requirement and cannot be approved."

  defp action_error(:contact_plan_decision_reason_required), do: "Enter a decision reason."
  defp action_error(:contact_plan_transition_reason_required), do: "Enter a review note."

  defp action_error(_reason),
    do: "Cadence could not apply that Plan action. Durable evidence was preserved."

  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %Y %H:%MZ")
  defp humanize(item), do: item |> to_string() |> String.replace("_", " ")
end
