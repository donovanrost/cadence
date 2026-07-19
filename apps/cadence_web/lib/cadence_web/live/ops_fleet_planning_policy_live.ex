defmodule CadenceWeb.OpsFleetPlanningPolicyLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.FleetPlanningPolicies

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Fleet Planning Policy")
      |> assign(:ops_nav_item, :planning)
      |> assign(:organization_admin?, organization_admin?(socket.assigns.current_scope))
      |> assign(:decision_form, to_form(%{"reason" => ""}, as: :decision))
      |> assign(
        :revocation_form,
        to_form(%{"automation_grant_id" => "", "reason" => ""}, as: :revocation)
      )
      |> stream_configure(:automation_grants,
        dom_id: &"automation-grant-#{&1.automation_grant_id}"
      )
      |> load_policy()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate-policy", %{"policy" => params}, socket) do
    {:noreply, assign(socket, :policy_form, to_form(params, as: :policy))}
  end

  def handle_event("save-policy", %{"policy" => params}, socket) do
    %{current_scope: scope, current_mission: mission, policy: policy} = socket.assigns

    with {:ok, attrs} <- policy_attrs(params),
         {:ok, _policy, _version} <-
           save_policy(scope, mission.mission_id, policy, attrs) do
      {:noreply,
       socket
       |> load_policy()
       |> put_flash(
         :info,
         if(policy, do: "Draft policy version created.", else: "Draft policy created.")
       )}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_event("approve-policy", %{"decision" => %{"reason" => reason}}, socket) do
    %{current_scope: scope, current_mission: mission, policy: policy, policy_version: version} =
      socket.assigns

    case FleetPlanningPolicies.approve(
           scope,
           mission.mission_id,
           policy.fleet_planning_policy_id,
           version.version,
           version.content_sha256,
           reason
         ) do
      {:ok, _policy, _version, _approval} ->
        {:noreply,
         socket
         |> load_policy()
         |> put_flash(:info, "Exact policy version approved and activated.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_event("validate-grant", %{"grant" => params}, socket) do
    {:noreply, assign(socket, :grant_form, to_form(params, as: :grant))}
  end

  def handle_event("issue-grant", %{"grant" => params}, socket) do
    %{current_scope: scope, current_mission: mission, active_policy_version: policy} =
      socket.assigns

    with %{} <- policy,
         {:ok, attrs} <- grant_attrs(params, policy),
         {:ok, _grant} <-
           Cadence.issue_automation_grant(scope, mission.mission_id, attrs) do
      {:noreply,
       socket
       |> load_policy()
       |> put_flash(:info, "Exact service automation grant issued.")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
      _no_policy -> {:noreply, put_flash(socket, :error, "Approve a policy first.")}
    end
  end

  def handle_event(
        "revoke-grant",
        %{"revocation" => %{"automation_grant_id" => grant_id, "reason" => reason}},
        socket
      ) do
    %{current_scope: scope, current_mission: mission, grants: grants} = socket.assigns

    case Enum.find(grants, &(&1.automation_grant_id == grant_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Select an active grant.")}

      grant ->
        case Cadence.revoke_automation_grant(
               scope,
               mission.mission_id,
               grant.automation_grant_id,
               grant.content_sha256,
               reason
             ) do
          {:ok, _revoked} ->
            {:noreply,
             socket
             |> load_policy()
             |> put_flash(:info, "Automation grant revoked immediately.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, action_error(reason))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-fleet-planning-policy-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto max-w-[100rem]">
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning"}
              class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
            >
              <.icon name="hero-arrow-left" class="h-3.5 w-3.5" /> Fleet planning
            </.link>
            <div class="mt-4 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
              <div>
                <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
                  Administrative boundary
                </p>
                <h1 class="mt-1 text-2xl font-bold tracking-tight">Fleet Policy & Automation</h1>
                <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                  Operators declare mission needs. Organization administrators approve the bounded horizon, capacity, cost, repair, and unattended authority Cadence may use.
                </p>
              </div>
              <span
                id="fleet-policy-state"
                class={policy_state_class(@policy)}
              >
                {policy_state_label(@policy)}
              </span>
            </div>
          </div>
        </header>

        <div class="mx-auto grid max-w-[100rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.25fr)_minmax(24rem,0.75fr)] lg:p-7">
          <div class="min-w-0 space-y-5">
            <section id="fleet-policy-manifest" class="border border-base-300 bg-base-200/15">
              <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3">
                <div>
                  <p class="hud-label">Current immutable version</p>
                  <p class="mt-1 font-mono text-sm">
                    {if @policy_version, do: "v#{@policy_version.version}", else: "not configured"}
                  </p>
                </div>
                <p :if={@policy_version} class="max-w-md break-all text-right font-mono text-[0.58rem] text-base-content/40">
                  {@policy_version.content_sha256}
                </p>
              </div>

              <%= if @policy_version do %>
                <div class="grid md:grid-cols-2">
                  <.policy_section
                    title="Horizon & search"
                    facts={[
                      {"Maximum horizon", hours(@policy_version.horizon_document["max_horizon_seconds"])},
                      {"Requirement workers", @policy_version.horizon_document["requirement_concurrency"]},
                      {"Provider workers", @policy_version.horizon_document["provider_search_concurrency"]},
                      {"Evidence reuse", "#{@policy_version.horizon_document["reuse_freshness_seconds"]} sec"}
                    ]}
                  />
                  <.policy_section
                    title="Quota & budget"
                    facts={[
                      {"Contact ceiling", @policy_version.budget_quota_document["max_contacts"] || "none"},
                      {"Cost ceiling", format_cost(@policy_version.budget_quota_document)},
                      {"Critical reserve", @policy_version.budget_quota_document["critical_contact_reserve"]},
                      {"Default capacity", @policy_version.resource_policy_document["default_exclusive_capacity"]}
                    ]}
                  />
                  <.policy_section
                    title="Automation"
                    facts={[
                      {"Mode", humanize(@policy_version.automation_repair_document["mode"])},
                      {"Automatic submission", yes_no(@policy_version.automation_repair_document["automatic_submission"])},
                      {"Execution workers", @policy_version.automation_repair_document["execution_concurrency"]},
                      {"Repair attempts", @policy_version.automation_repair_document["max_repair_attempts"]}
                    ]}
                  />
                  <.policy_section
                    title="Redundancy"
                    facts={[
                      {"Distinct provider", yes_no(@policy_version.redundancy_document["distinct_provider_required"])},
                      {"Distinct station", yes_no(@policy_version.redundancy_document["distinct_station_required"])},
                      {"Distinct pool", yes_no(@policy_version.redundancy_document["distinct_service_pool_required"])},
                      {"Repair horizon", hours(@policy_version.automation_repair_document["repair_horizon_seconds"])}
                    ]}
                  />
                </div>
              <% else %>
                <div id="fleet-policy-empty" class="px-6 py-14 text-center">
                  <.icon name="hero-adjustments-horizontal" class="mx-auto h-8 w-8 text-warning/50" />
                  <h2 class="mt-4 text-base font-semibold">No scheduling boundary exists</h2>
                  <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/55">
                    Fleet runs and automation remain stopped until an administrator creates and approves a policy.
                  </p>
                </div>
              <% end %>
            </section>

            <section
              :if={@organization_admin?}
              id="fleet-policy-editor"
              class="border border-base-300 bg-base-200/15"
            >
              <details open={is_nil(@policy)}>
                <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
                  {if @policy, do: "Draft a new immutable version", else: "Create the initial policy"}
                </summary>
                <.form
                  for={@policy_form}
                  id="fleet-policy-form"
                  phx-change="validate-policy"
                  phx-submit="save-policy"
                  class="space-y-5 border-t border-base-300 p-4"
                >
                  <div>
                    <p class="hud-label">Search boundary</p>
                    <div class="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                      <.input id="policy-max-horizon-hours" field={@policy_form[:max_horizon_hours]} type="number" min="1" label="Maximum hours" required />
                      <.input id="policy-requirement-concurrency" field={@policy_form[:requirement_concurrency]} type="number" min="1" label="Requirement workers" required />
                      <.input id="policy-provider-concurrency" field={@policy_form[:provider_search_concurrency]} type="number" min="1" label="Provider workers" required />
                      <.input id="policy-reuse-seconds" field={@policy_form[:reuse_freshness_seconds]} type="number" min="0" label="Reuse seconds" required />
                    </div>
                  </div>

                  <div>
                    <p class="hud-label">Capacity & budget</p>
                    <div class="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                      <.input id="policy-max-contacts" field={@policy_form[:max_contacts]} type="number" min="1" label="Contact ceiling" required />
                      <.input id="policy-max-cost" field={@policy_form[:max_estimated_cost_micros]} type="number" min="0" label="Cost micros (optional)" />
                      <.input id="policy-currency" field={@policy_form[:currency]} type="text" label="Currency" />
                      <.input id="policy-critical-reserve" field={@policy_form[:critical_contact_reserve]} type="number" min="0" label="Critical reserve" required />
                    </div>
                  </div>

                  <div>
                    <p class="hud-label">Automation & repair</p>
                    <div class="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                      <.input
                        id="policy-automation-mode"
                        field={@policy_form[:automation_mode]}
                        type="select"
                        label="Mode"
                        options={[
                          {"Advisory", "advisory"},
                          {"Approval required", "approval_required"},
                          {"Bounded automatic", "bounded_automatic"}
                        ]}
                      />
                      <.input id="policy-execution-concurrency" field={@policy_form[:execution_concurrency]} type="number" min="1" label="Execution workers" required />
                      <.input id="policy-repair-attempts" field={@policy_form[:max_repair_attempts]} type="number" min="0" label="Repair attempts" required />
                      <.input id="policy-repair-horizon-hours" field={@policy_form[:repair_horizon_hours]} type="number" min="1" label="Repair hours" required />
                    </div>
                    <.input
                      :if={@policy_form[:automation_mode].value != "advisory"}
                      id="policy-automatic-submission"
                      field={@policy_form[:automatic_submission]}
                      type="checkbox"
                      label="Allow exact candidate Plans to be submitted automatically"
                    />
                  </div>

                  <details id="fleet-policy-redundancy-details" class="border border-base-300">
                    <summary class="cursor-pointer px-3 py-2 text-xs font-semibold">
                      Redundancy constraints
                    </summary>
                    <div class="grid gap-3 border-t border-base-300 p-3 sm:grid-cols-3">
                      <.input id="policy-distinct-provider" field={@policy_form[:distinct_provider_required]} type="checkbox" label="Distinct providers" />
                      <.input id="policy-distinct-station" field={@policy_form[:distinct_station_required]} type="checkbox" label="Distinct stations" />
                      <.input id="policy-distinct-pool" field={@policy_form[:distinct_service_pool_required]} type="checkbox" label="Distinct service pools" />
                    </div>
                  </details>

                  <button id="save-fleet-policy" type="submit" class="btn btn-primary btn-sm w-full">
                    {if @policy, do: "Create draft version", else: "Create draft policy"}
                  </button>
                </.form>
              </details>
            </section>

            <section
              :if={@organization_admin? and approvable?(@policy, @policy_version)}
              id="fleet-policy-approval"
              class="border border-primary/35 bg-primary/[0.035] p-4"
            >
              <p class="hud-label">Activate exact version</p>
              <p class="mt-2 text-sm text-base-content/60">
                Approval invalidates grants tied to an older policy version and changes the boundary for future runs.
              </p>
              <.form
                for={@decision_form}
                id="fleet-policy-approval-form"
                phx-submit="approve-policy"
                class="mt-4"
              >
                <.input id="fleet-policy-approval-reason" field={@decision_form[:reason]} type="textarea" label="Approval reason" required />
                <button id="approve-fleet-policy" type="submit" class="btn btn-primary btn-sm w-full">
                  Approve exact v{@policy_version.version}
                </button>
              </.form>
            </section>
          </div>

          <aside class="min-w-0 space-y-5">
            <section id="automation-grant-ledger" class="border border-base-300 bg-base-200/15">
              <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
                <div>
                  <p class="hud-label">Automation grants</p>
                  <p class="mt-1 text-xs text-base-content/50">Exact service + policy authority</p>
                </div>
                <span class="font-mono text-xs text-base-content/45">{@active_grant_count} active</span>
              </div>
              <div id="automation-grants" phx-update="stream">
                <div id="automation-grants-empty" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">
                  No automation authority issued.
                </div>
                <div
                  :for={{dom_id, grant} <- @streams.automation_grants}
                  id={dom_id}
                  class="border-b border-base-300 p-4 last:border-b-0"
                >
                  <div class="flex items-center justify-between gap-3">
                    <p class="truncate text-xs font-semibold">{grant.service_identity_id}</p>
                    <span class={grant_state_class(grant.lifecycle_state)}>
                      {grant.lifecycle_state}
                    </span>
                  </div>
                  <p class="mt-2 font-mono text-[0.58rem] text-base-content/40">
                    policy v{grant.fleet_planning_policy_version} · {Enum.join(Enum.map(grant.allowed_actions, &Atom.to_string/1), ", ")}
                  </p>
                  <p class="mt-2 text-xs text-base-content/55">
                    ≤ {grant.maximum_contacts} contacts · ≤ {hours(grant.maximum_horizon_seconds)}
                  </p>
                  <p class="mt-2 font-mono text-[0.56rem] text-base-content/35">
                    expires {format_time(grant.valid_until)}
                  </p>
                </div>
              </div>
            </section>

            <section
              :if={
                @organization_admin? and not is_nil(@active_policy_version) and
                  @service_identity_options != []
              }
              id="automation-grant-issuer"
              class="border border-base-300 bg-base-200/15"
            >
              <details>
                <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
                  Issue bounded authority
                </summary>
                <.form
                  for={@grant_form}
                  id="automation-grant-form"
                  phx-change="validate-grant"
                  phx-submit="issue-grant"
                  class="space-y-4 border-t border-base-300 p-4"
                >
                  <.input id="grant-service-identity" field={@grant_form[:service_identity_id]} type="select" label="Mission service identity" options={@service_identity_options} required />
                  <div class="grid gap-3 sm:grid-cols-2">
                    <.input id="grant-max-horizon-hours" field={@grant_form[:maximum_horizon_hours]} type="number" min="1" label="Maximum hours" required />
                    <.input id="grant-max-contacts" field={@grant_form[:maximum_contacts]} type="number" min="1" label="Maximum contacts" required />
                    <.input id="grant-execution-concurrency" field={@grant_form[:maximum_execution_concurrency]} type="number" min="1" label="Execution workers" required />
                    <.input id="grant-valid-days" field={@grant_form[:valid_days]} type="number" min="1" label="Valid days" required />
                  </div>
                  <.input id="grant-approval-reason" field={@grant_form[:approval_reason]} type="textarea" label="Why this unattended authority is appropriate" required />
                  <button id="issue-automation-grant" type="submit" class="btn btn-primary btn-sm w-full">
                    Issue exact grant
                  </button>
                </.form>
              </details>
            </section>

            <section
              :if={@organization_admin? and @active_grant_options != []}
              id="automation-grant-revoker"
              class="border border-error/25 bg-error/[0.025]"
            >
              <details>
                <summary class="cursor-pointer px-4 py-3 text-sm font-semibold text-error">
                  Revoke automation authority
                </summary>
                <.form
                  for={@revocation_form}
                  id="automation-grant-revocation-form"
                  phx-submit="revoke-grant"
                  class="space-y-3 border-t border-error/20 p-4"
                >
                  <.input id="revoke-automation-grant-id" field={@revocation_form[:automation_grant_id]} type="select" label="Active grant" options={@active_grant_options} required />
                  <.input id="revoke-automation-grant-reason" field={@revocation_form[:reason]} type="textarea" label="Revocation reason" required />
                  <button id="revoke-automation-grant" type="submit" class="btn btn-error btn-sm w-full">
                    Revoke immediately
                  </button>
                </.form>
              </details>
            </section>

            <p
              :if={not @organization_admin?}
              id="fleet-policy-admin-required"
              class="border-l-2 border-warning px-3 text-xs text-warning"
            >
              Organization administrator authority is required to change policy or grants.
            </p>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :facts, :list, required: true

  defp policy_section(assigns) do
    ~H"""
    <div class="border-b border-base-300 p-4 last:border-b-0 md:border-r md:odd:border-r md:even:border-r-0">
      <p class="hud-label">{@title}</p>
      <dl class="mt-3 space-y-2 text-xs">
        <div :for={{term, value} <- @facts} class="flex items-center justify-between gap-4">
          <dt class="text-base-content/50">{term}</dt>
          <dd class="font-mono text-right text-base-content/75">{value}</dd>
        </div>
      </dl>
    </div>
    """
  end

  defp load_policy(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    {policy, version} =
      case FleetPlanningPolicies.fetch(scope.organization_id, mission.mission_id) do
        {:ok, policy, version} -> {policy, version}
        {:error, _reason} -> {nil, nil}
      end

    active_version =
      case FleetPlanningPolicies.fetch_active(
             scope.organization_id,
             mission.mission_id
           ) do
        {:ok, _policy, version} -> version
        {:error, _reason} -> nil
      end

    grants = Cadence.list_automation_grants(scope.organization_id, mission.mission_id)
    active_grants = Enum.filter(grants, &(&1.lifecycle_state == :active))

    service_identities =
      scope.organization_id
      |> Cadence.Auth.list_service_identities(lifecycle_state: :active)
      |> Enum.filter(&(&1.mission_id == mission.mission_id))

    policy_form = to_form(policy_form_params(version), as: :policy)
    grant_form = to_form(grant_form_params(active_version, service_identities), as: :grant)

    socket
    |> assign(:policy, policy)
    |> assign(:policy_version, version)
    |> assign(:active_policy_version, active_version)
    |> assign(:policy_form, policy_form)
    |> assign(:grant_form, grant_form)
    |> assign(:grants, grants)
    |> assign(:active_grant_count, length(active_grants))
    |> assign(
      :service_identity_options,
      Enum.map(service_identities, &{&1.display_name, &1.service_identity_id})
    )
    |> assign(
      :active_grant_options,
      Enum.map(active_grants, &{&1.service_identity_id, &1.automation_grant_id})
    )
    |> stream(:automation_grants, grants, reset: true)
  end

  defp save_policy(scope, mission_id, nil, attrs),
    do: FleetPlanningPolicies.create(scope, mission_id, attrs)

  defp save_policy(scope, mission_id, policy, attrs) do
    FleetPlanningPolicies.version(
      scope,
      mission_id,
      policy.fleet_planning_policy_id,
      policy.current_version,
      attrs
    )
  end

  defp policy_attrs(params) do
    with {:ok, max_horizon_hours} <- positive_integer(params["max_horizon_hours"]),
         {:ok, requirement_concurrency} <- positive_integer(params["requirement_concurrency"]),
         {:ok, provider_concurrency} <- positive_integer(params["provider_search_concurrency"]),
         {:ok, reuse_seconds} <- non_negative_integer(params["reuse_freshness_seconds"]),
         {:ok, max_contacts} <- positive_integer(params["max_contacts"]),
         {:ok, max_cost} <- optional_non_negative_integer(params["max_estimated_cost_micros"]),
         {:ok, critical_reserve} <- non_negative_integer(params["critical_contact_reserve"]),
         {:ok, execution_concurrency} <- positive_integer(params["execution_concurrency"]),
         {:ok, repair_attempts} <- non_negative_integer(params["max_repair_attempts"]),
         {:ok, repair_horizon_hours} <- positive_integer(params["repair_horizon_hours"]) do
      mode = params["automation_mode"] || "advisory"
      automatic_submission = mode != "advisory" and truthy?(params["automatic_submission"])
      currency = blank_to_nil(params["currency"])

      {:ok,
       %{
         horizon_document: %{
           "max_horizon_seconds" => max_horizon_hours * 3_600,
           "requirement_concurrency" => requirement_concurrency,
           "provider_search_concurrency" => provider_concurrency,
           "reuse_freshness_seconds" => reuse_seconds
         },
         scoring_document: %{},
         resource_policy_document: %{},
         budget_quota_document: %{
           "max_contacts" => max_contacts,
           "max_estimated_cost_micros" => max_cost,
           "currency" => if(max_cost, do: currency || "USD", else: nil),
           "per_provider" => %{},
           "critical_contact_reserve" => critical_reserve,
           "critical_cost_reserve_micros" => 0
         },
         redundancy_document: %{
           "distinct_provider_required" => truthy?(params["distinct_provider_required"]),
           "distinct_station_required" => truthy?(params["distinct_station_required"]),
           "distinct_service_pool_required" => truthy?(params["distinct_service_pool_required"])
         },
         automation_repair_document: %{
           "mode" => mode,
           "execution_concurrency" => execution_concurrency,
           "max_repair_attempts" => repair_attempts,
           "repair_horizon_seconds" => repair_horizon_hours * 3_600,
           "automatic_submission" => automatic_submission
         }
       }}
    else
      {:error, _reason} -> {:error, :invalid_fleet_policy_form}
    end
  end

  defp grant_attrs(params, policy) do
    with service_identity_id when is_binary(service_identity_id) and service_identity_id != "" <-
           params["service_identity_id"],
         {:ok, horizon_hours} <- positive_integer(params["maximum_horizon_hours"]),
         {:ok, maximum_contacts} <- positive_integer(params["maximum_contacts"]),
         {:ok, concurrency} <- positive_integer(params["maximum_execution_concurrency"]),
         {:ok, valid_days} <- positive_integer(params["valid_days"]),
         reason when is_binary(reason) and reason != "" <-
           String.trim(params["approval_reason"] || "") do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      budget = policy.budget_quota_document

      {:ok,
       %{
         service_identity_id: service_identity_id,
         allowed_actions: allowed_actions(policy),
         maximum_horizon_seconds: horizon_hours * 3_600,
         maximum_contacts: maximum_contacts,
         maximum_estimated_cost_micros: budget["max_estimated_cost_micros"],
         currency: budget["currency"],
         maximum_execution_concurrency: concurrency,
         valid_from: now,
         valid_until: DateTime.add(now, valid_days, :day),
         approval_reason: reason
       }}
    else
      _reason -> {:error, :invalid_automation_grant_form}
    end
  end

  defp allowed_actions(policy) do
    automation = policy.automation_repair_document
    base = [:plan, :repair]
    base = if automation["mode"] != "advisory", do: [:execute | base], else: base
    base = if automation["automatic_submission"], do: [:submit | base], else: base

    base =
      if automation["mode"] == "bounded_automatic" and automation["automatic_submission"],
        do: [:approve | base],
        else: base

    Enum.uniq(base)
  end

  defp policy_form_params(nil) do
    %{
      "max_horizon_hours" => "24",
      "requirement_concurrency" => "8",
      "provider_search_concurrency" => "4",
      "reuse_freshness_seconds" => "300",
      "max_contacts" => "500",
      "max_estimated_cost_micros" => "",
      "currency" => "",
      "critical_contact_reserve" => "0",
      "automation_mode" => "advisory",
      "execution_concurrency" => "4",
      "max_repair_attempts" => "3",
      "repair_horizon_hours" => "24",
      "automatic_submission" => "false",
      "distinct_provider_required" => "false",
      "distinct_station_required" => "false",
      "distinct_service_pool_required" => "false"
    }
  end

  defp policy_form_params(version) do
    %{
      "max_horizon_hours" =>
        Integer.to_string(div(version.horizon_document["max_horizon_seconds"], 3_600)),
      "requirement_concurrency" =>
        Integer.to_string(version.horizon_document["requirement_concurrency"]),
      "provider_search_concurrency" =>
        Integer.to_string(version.horizon_document["provider_search_concurrency"]),
      "reuse_freshness_seconds" =>
        Integer.to_string(version.horizon_document["reuse_freshness_seconds"]),
      "max_contacts" => to_form_string(version.budget_quota_document["max_contacts"]),
      "max_estimated_cost_micros" =>
        to_form_string(version.budget_quota_document["max_estimated_cost_micros"]),
      "currency" => version.budget_quota_document["currency"] || "",
      "critical_contact_reserve" =>
        Integer.to_string(version.budget_quota_document["critical_contact_reserve"]),
      "automation_mode" => version.automation_repair_document["mode"],
      "execution_concurrency" =>
        Integer.to_string(version.automation_repair_document["execution_concurrency"]),
      "max_repair_attempts" =>
        Integer.to_string(version.automation_repair_document["max_repair_attempts"]),
      "repair_horizon_hours" =>
        Integer.to_string(
          div(version.automation_repair_document["repair_horizon_seconds"], 3_600)
        ),
      "automatic_submission" =>
        to_string(version.automation_repair_document["automatic_submission"]),
      "distinct_provider_required" =>
        to_string(version.redundancy_document["distinct_provider_required"]),
      "distinct_station_required" =>
        to_string(version.redundancy_document["distinct_station_required"]),
      "distinct_service_pool_required" =>
        to_string(version.redundancy_document["distinct_service_pool_required"])
    }
  end

  defp grant_form_params(nil, service_identities),
    do:
      grant_form_params(
        %{horizon_document: %{}, budget_quota_document: %{}, automation_repair_document: %{}},
        service_identities
      )

  defp grant_form_params(policy, service_identities) do
    %{
      "service_identity_id" =>
        case service_identities do
          [identity | _rest] -> identity.service_identity_id
          [] -> ""
        end,
      "maximum_horizon_hours" =>
        policy.horizon_document
        |> Map.get("max_horizon_seconds", 86_400)
        |> div(3_600)
        |> Integer.to_string(),
      "maximum_contacts" =>
        policy.budget_quota_document
        |> Map.get("max_contacts", 100)
        |> Kernel.||(100)
        |> Integer.to_string(),
      "maximum_execution_concurrency" =>
        policy.automation_repair_document
        |> Map.get("execution_concurrency", 1)
        |> Integer.to_string(),
      "valid_days" => "30",
      "approval_reason" => ""
    }
  end

  defp approvable?(nil, _version), do: false

  defp approvable?(policy, version),
    do: policy.active_version != version.version and policy.lifecycle_state != :retired

  defp organization_admin?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end

  defp positive_integer(value) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_positive_integer}
    end
  end

  defp non_negative_integer(value) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _other -> {:error, :invalid_non_negative_integer}
    end
  end

  defp optional_non_negative_integer(value) when value in [nil, ""], do: {:ok, nil}
  defp optional_non_negative_integer(value), do: non_negative_integer(value)
  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value |> String.trim() |> String.upcase()
  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp to_form_string(nil), do: ""
  defp to_form_string(value), do: to_string(value)
  defp hours(seconds), do: "#{Float.round(seconds / 3_600, 1)} h"
  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"

  defp format_cost(%{"max_estimated_cost_micros" => nil}), do: "none"

  defp format_cost(document),
    do: "#{document["max_estimated_cost_micros"]} #{document["currency"]} micros"

  defp policy_state_class(nil),
    do:
      "border border-warning/40 bg-warning/10 px-2 py-1 font-mono text-xs uppercase text-warning"

  defp policy_state_class(%{lifecycle_state: :active}),
    do:
      "border border-success/35 bg-success/10 px-2 py-1 font-mono text-xs uppercase text-success"

  defp policy_state_class(_policy),
    do:
      "border border-primary/35 bg-primary/10 px-2 py-1 font-mono text-xs uppercase text-primary"

  defp policy_state_label(nil), do: "stopped"
  defp policy_state_label(policy), do: humanize(policy.lifecycle_state)

  defp grant_state_class(:active),
    do: "font-mono text-[0.58rem] uppercase text-success"

  defp grant_state_class(_state),
    do: "font-mono text-[0.58rem] uppercase text-base-content/45"

  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %Y %H:%MZ")
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp action_error(:forbidden), do: "Organization administrator authority is required."
  defp action_error(:automation_grant_policy_drift), do: "The policy changed; issue a new grant."
  defp action_error(:invalid_fleet_policy_form), do: "Review the policy values and try again."
  defp action_error(:invalid_automation_grant_form), do: "Complete every grant boundary."
  defp action_error(_reason), do: "The policy operation could not be completed."
end
