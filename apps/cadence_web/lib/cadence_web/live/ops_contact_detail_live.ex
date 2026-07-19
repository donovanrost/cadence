defmodule CadenceWeb.OpsContactDetailLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Contacts.{
    ProviderChangeApprovals,
    ProviderReservationChanges,
    ProviderReservations,
    ScheduledContactRevisions
  }

  alias Cadence.GroundNetworks.{
    DeliveryPolicy,
    MissionProviders,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderAudit
  }

  @decision_states [:pending_approval, :acknowledgment_required]

  @impl true
  def mount(%{"provider_reservation_id" => reservation_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case ProviderReservations.fetch(scope.organization_id, mission.mission_id, reservation_id) do
      {:ok, reservation} ->
        socket =
          socket
          |> stream_configure(:provider_changes,
            dom_id: &"provider-change-#{&1.provider_reservation_change_id}"
          )
          |> stream_configure(:provider_audit_entries,
            dom_id: &"provider-audit-#{&1.provider_audit_entry_id}"
          )
          |> assign(:page_title, "Contact #{reservation.provider_reservation_id}")
          |> assign(:ops_nav_item, :contacts)
          |> assign(:provider_reservation_id, reservation.provider_reservation_id)
          |> refresh()

        {:ok, socket}

      {:error, :provider_reservation_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That provider Contact is not available in this mission.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/contacts")}
    end
  end

  @impl true
  def handle_event("approve-provider-change", %{"approval" => params}, socket) do
    decide(socket, :approve, params)
  end

  def handle_event("reject-provider-change", %{"rejection" => params}, socket) do
    decide(socket, :reject, params)
  end

  def handle_event("acknowledge-provider-change", %{"acknowledgment" => params}, socket) do
    decide(socket, :acknowledge, params)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="ops-contact-detail" class="h-full overflow-y-auto bg-base-100">
      <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
        <div class="mx-auto flex max-w-[96rem] flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
          <div class="min-w-0">
            <.link
              id="back-to-contact-schedule"
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/contacts"}
              class="inline-flex items-center gap-1 font-mono text-[0.65rem] uppercase tracking-[0.18em] text-primary/70 hover:text-primary"
            >
              <.icon name="hero-arrow-left" class="h-3 w-3" /> Contact ledger
            </.link>
            <div class="mt-3 flex flex-wrap items-center gap-3">
              <h1 class="text-2xl font-bold tracking-tight text-base-content">Contact record</h1>
              <.state_badge state={@reservation.lifecycle_state} />
            </div>
            <p class="mt-2 truncate font-mono text-xs text-base-content/50">
              {@reservation.provider_reservation_id}
            </p>
          </div>

          <div class="grid grid-cols-3 gap-px border border-primary/20 bg-primary/20 font-mono text-xs">
            <.header_fact label="Provider rev" value={@reservation.provider_revision} />
            <.header_fact label="Schedule rev" value={schedule_revision(@scheduled_contact)} />
            <.header_fact label="Decision work" value={decision_label(@current_change)} />
          </div>
        </div>
      </header>

      <div class="mx-auto grid max-w-[96rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(20rem,0.62fr)] lg:p-7">
        <main class="min-w-0 space-y-5">
          <section id="contact-values-matrix" class="border border-base-300 bg-base-200/20">
            <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">
              <div>
                <p class="hud-label">Truth ledger</p>
                <h2 class="mt-1 text-base font-semibold">Four values, one operational record</h2>
                <p class="mt-1 text-xs text-base-content/55">
                  Provider truth does not silently become Cadence execution truth.
                </p>
              </div>
              <.icon name="hero-table-cells" class="h-5 w-5 text-primary/60" />
            </div>

            <div class="overflow-x-auto">
              <table class="w-full min-w-[48rem] table-fixed border-collapse text-left text-xs">
                <thead class="font-mono uppercase tracking-[0.12em] text-base-content/40">
                  <tr>
                    <th class="w-32 border-b border-r border-base-300 px-3 py-2">Field</th>
                    <th class="border-b border-r border-base-300 px-3 py-2">Requested</th>
                    <th class="border-b border-r border-base-300 px-3 py-2">Provider confirmed</th>
                    <th class="border-b border-r border-base-300 px-3 py-2">Cadence accepted</th>
                    <th class="border-b border-base-300 px-3 py-2">Actual / projected</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @value_rows} id={"contact-value-#{row.id}"}>
                    <th class="border-r border-t border-base-300 bg-base-200/60 px-3 py-2 font-mono text-base-content/50">
                      {row.label}
                    </th>
                    <.value_cell value={row.requested} />
                    <.value_cell value={row.confirmed} />
                    <.value_cell value={row.accepted} />
                    <td class="border-t border-base-300 px-3 py-2 font-mono text-base-content/75">
                      {row.actual}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section id="contact-change-control" class="border border-base-300 bg-base-200/20">
            <div class="border-b border-base-300 px-4 py-3">
              <p class="hud-label">Provider revision control</p>
              <h2 class="mt-1 text-base font-semibold">Changes and decisions</h2>
            </div>

            <div id="contact-change-timeline" phx-update="stream">
              <div id="contact-change-timeline-empty" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">
                No provider revisions beyond the accepted baseline.
              </div>
              <article
                :for={{dom_id, change} <- @streams.provider_changes}
                id={dom_id}
                class="grid gap-4 border-b border-base-300/70 px-4 py-4 lg:grid-cols-[8rem_minmax(0,1fr)]"
              >
                <div>
                  <p class="font-mono text-[0.62rem] uppercase tracking-[0.14em] text-base-content/40">
                    Provider revision
                  </p>
                  <p class="mt-1 font-mono text-lg font-bold text-primary">
                    {change.from_provider_revision} → {change.provider_revision}
                  </p>
                  <.change_state state={change.lifecycle_state} />
                </div>

                <div class="min-w-0">
                  <div class="flex flex-wrap items-center justify-between gap-2">
                    <p class="text-sm font-semibold">{classification_title(change.classification)}</p>
                    <span class="font-mono text-[0.64rem] text-base-content/40">
                      Policy v{change.policy_version}
                    </span>
                  </div>
                  <p class="mt-2 text-xs leading-relaxed text-base-content/60">
                    {change_explanation(change)}
                  </p>
                  <div class="mt-3 flex flex-wrap gap-1.5">
                    <span
                      :for={field <- changed_field_names(change)}
                      class="border border-base-300 bg-base-200 px-2 py-1 font-mono text-[0.62rem] text-base-content/55"
                    >
                      {field}
                    </span>
                  </div>

                  <div :if={change.deadline_at} class="mt-3 border-l-2 border-warning/60 pl-3 text-xs text-warning">
                    Provider decision deadline: {format_time(change.deadline_at)}
                  </div>

                  <div
                    :if={change.lifecycle_state == :configuration_failure}
                    id={"configuration-remediation-#{change.provider_reservation_change_id}"}
                    class="mt-4 border-l-2 border-error bg-error/5 px-3 py-2"
                  >
                    <p class="text-xs font-semibold text-error">Never approvable from Contact data</p>
                    <p class="mt-1 text-xs text-base-content/60">
                      Reconcile the Mission Provider, Transport, credential, and delivery-profile configuration before retrying. Cadence has not rewritten execution.
                    </p>
                  </div>

                  <div
                    :if={@admin? and active_change?(change, @current_change, :pending_approval)}
                    class="mt-4 grid gap-3 border-t border-base-300 pt-4 lg:grid-cols-2"
                  >
                    <.form
                      for={@approval_form}
                      id={"provider-change-approval-form-#{change.provider_reservation_change_id}"}
                      phx-submit="approve-provider-change"
                      class="space-y-3 border border-success/30 bg-success/5 p-3"
                    >
                      <.input field={@approval_form[:proposal_hash]} type="hidden" />
                      <.input field={@approval_form[:reason]} type="textarea" label="Approval reason" required />
                      <button id={"approve-provider-change-#{change.provider_reservation_change_id}"} class="btn btn-success btn-sm w-full font-mono text-xs uppercase tracking-wider">
                        Approve current revision
                      </button>
                    </.form>

                    <.form
                      :if={change.actionable}
                      for={@rejection_form}
                      id={"provider-change-rejection-form-#{change.provider_reservation_change_id}"}
                      phx-submit="reject-provider-change"
                      class="space-y-3 border border-error/30 bg-error/5 p-3"
                    >
                      <.input field={@rejection_form[:proposal_hash]} type="hidden" />
                      <.input field={@rejection_form[:reason]} type="textarea" label="Rejection reason" required />
                      <button id={"reject-provider-change-#{change.provider_reservation_change_id}"} class="btn btn-error btn-outline btn-sm w-full font-mono text-xs uppercase tracking-wider">
                        Reject provider proposal
                      </button>
                    </.form>
                  </div>

                  <.form
                    :if={@admin? and active_change?(change, @current_change, :acknowledgment_required)}
                    for={@acknowledgment_form}
                    id={"provider-change-acknowledgment-form-#{change.provider_reservation_change_id}"}
                    phx-submit="acknowledge-provider-change"
                    class="mt-4 space-y-3 border border-warning/35 bg-warning/5 p-3"
                  >
                    <p class="text-xs font-semibold text-warning">Provider fact is already effective</p>
                    <p class="text-xs text-base-content/60">
                      Acknowledge the fact and record the contingency response. Approval or fictional rejection is unavailable.
                    </p>
                    <.input field={@acknowledgment_form[:proposal_hash]} type="hidden" />
                    <.input field={@acknowledgment_form[:reason]} type="textarea" label="Contingency note" required />
                    <button id={"acknowledge-provider-change-#{change.provider_reservation_change_id}"} class="btn btn-warning btn-sm font-mono text-xs uppercase tracking-wider">
                      Acknowledge provider fact
                    </button>
                  </.form>
                </div>
              </article>
            </div>
          </section>

          <section class="border border-base-300 bg-base-200/20">
            <div class="border-b border-base-300 px-4 py-3">
              <p class="hud-label">Evidence timeline</p>
              <h2 class="mt-1 text-base font-semibold">Provider audit</h2>
            </div>
            <ol id="contact-audit-timeline" phx-update="stream">
              <li id="contact-audit-timeline-empty" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">
                No provider audit entries recorded yet.
              </li>
              <li
                :for={{dom_id, entry} <- @streams.provider_audit_entries}
                id={dom_id}
                class="grid gap-3 border-b border-base-300/70 px-4 py-4 sm:grid-cols-[9rem_minmax(0,1fr)]"
              >
                <time class="font-mono text-[0.65rem] text-base-content/40">
                  {format_time(entry.recorded_at)}
                </time>
                <div>
                  <p class="font-mono text-xs font-semibold text-base-content/75">{entry.action}</p>
                  <p class="mt-1 text-xs text-base-content/55">Outcome: {entry.outcome}</p>
                  <div :if={entry.evidence_references != []} class="mt-2 space-y-1">
                    <p :for={reference <- entry.evidence_references} class="font-mono text-[0.62rem] text-primary/70">
                      Evidence {reference["provider_evidence_id"]} · sha256 {short_hash(reference["content_sha256"])}
                    </p>
                  </div>
                </div>
              </li>
            </ol>
          </section>
        </main>

        <aside class="min-w-0 space-y-5 xl:sticky xl:top-0 xl:self-start">
          <section id="contact-binding-chain" class="border border-base-300 bg-base-200/25">
            <div class="border-b border-base-300 px-4 py-3">
              <p class="hud-label">Immutable binding chain</p>
              <h2 class="mt-1 text-sm font-semibold">Execution ownership</h2>
            </div>
            <dl class="divide-y divide-base-300/70 text-xs">
              <.binding_row label="Provider Account" value={account_label(@provider_account_version, @reservation)} />
              <.binding_row label="Mission grant" value={grant_label(@provider_grant, @reservation)} />
              <.binding_row label="Mission Provider" value={versioned(@reservation.provider_id, @reservation.provider_version)} />
              <.binding_row label="Delivery policy" value={"v#{@delivery_policy_version}"} />
              <.binding_row label="Transport" value={versioned(@reservation.transport_id, @reservation.transport_version)} />
              <.binding_row label="Service Profile" value={profile_label(@reservation.service_profile_ref)} />
              <.binding_row label="Delivery Profile" value={profile_label(@reservation.delivery_profile_ref)} />
            </dl>
          </section>

          <section class="border border-base-300 bg-base-200/25">
            <div class="border-b border-base-300 px-4 py-3">
              <p class="hud-label">Independent lifecycle</p>
              <h2 class="mt-1 text-sm font-semibold">Operational state</h2>
            </div>
            <div class="grid grid-cols-2 gap-px bg-base-300/70">
              <.lifecycle_cell label="Provider Contact" value={@reservation.provider_status || @reservation.lifecycle_state} />
              <.lifecycle_cell label="Provider pass" value={@reservation.pass_phase} />
              <.lifecycle_cell label="Delivery" value={@reservation.delivery_state} />
              <.lifecycle_cell label="Cadence schedule" value={contact_lifecycle(@scheduled_contact)} />
              <.lifecycle_cell label="Actual contact" value={realized_lifecycle(@realized_contact)} />
              <.lifecycle_cell label="Reservation" value={@reservation.lifecycle_state} />
            </div>
          </section>

          <details
            :if={@admin?}
            id="contact-admin-diagnostics"
            class="border border-base-300 bg-base-200/25"
          >
            <summary class="cursor-pointer border-b border-base-300 px-4 py-3 font-mono text-[0.68rem] uppercase tracking-[0.16em] text-base-content/55 hover:text-primary">
              Administrator diagnostics
            </summary>
            <dl class="space-y-3 p-4 font-mono text-[0.65rem] text-base-content/60">
              <.diagnostic_row label="Protocol" value={descriptor_value(@reservation, "protocol")} />
              <.diagnostic_row label="Endpoint" value={descriptor_value(@reservation, "endpoint_ref")} />
              <.diagnostic_row label="Framing" value={framing_label(@reservation)} />
              <.diagnostic_row label="Credential ref" value={credential_label(@provider_account_version)} />
              <.diagnostic_row label="Provider contact" value={@reservation.provider_contact_ref || "not assigned"} />
              <.diagnostic_row label="Provider opportunity" value={@reservation.provider_opportunity_ref} />
              <.diagnostic_row label="Client reference" value={@reservation.idempotency_key} />
            </dl>
            <.link
              :if={@reservation.provider_account_id}
              id="contact-provider-ingestion-link"
              navigate={~p"/provider-accounts/#{@reservation.provider_account_id}"}
              class="mx-4 mb-4 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
            >
              Cursor and quarantine diagnostics <.icon name="hero-arrow-up-right" class="h-3 w-3" />
            </.link>
          </details>
        </aside>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp header_fact(assigns) do
    ~H"""
    <div class="min-w-24 bg-base-200/90 px-3 py-2">
      <p class="text-[0.58rem] uppercase tracking-[0.14em] text-base-content/35">{@label}</p>
      <p class="mt-1 font-semibold text-primary">{@value}</p>
    </div>
    """
  end

  attr :value, :any, required: true

  defp value_cell(assigns) do
    ~H"""
    <td class="border-r border-t border-base-300 px-3 py-2 font-mono text-base-content/65 last:border-r-0">
      {@value}
    </td>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp binding_row(assigns) do
    ~H"""
    <div class="px-4 py-3">
      <dt class="hud-label">{@label}</dt>
      <dd class="mt-1 break-all font-mono text-[0.68rem] text-base-content/70">{@value}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp lifecycle_cell(assigns) do
    ~H"""
    <div class="bg-base-200/80 px-3 py-3">
      <p class="hud-label">{@label}</p>
      <p class="mt-1 font-mono text-[0.68rem] font-semibold uppercase text-base-content/70">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp diagnostic_row(assigns) do
    ~H"""
    <div>
      <dt class="text-base-content/35">{@label}</dt>
      <dd class="mt-0.5 break-all">{@value}</dd>
    </div>
    """
  end

  attr :state, :atom, required: true

  defp state_badge(assigns) do
    ~H"""
    <span class={["border px-2 py-1 font-mono text-[0.62rem] font-bold uppercase tracking-wider", state_class(@state)]}>
      {@state}
    </span>
    """
  end

  attr :state, :atom, required: true

  defp change_state(assigns) do
    ~H"""
    <p class="mt-2 font-mono text-[0.62rem] font-semibold uppercase tracking-[0.12em] text-base-content/55">
      {@state}
    </p>
    """
  end

  defp decide(socket, action, params) do
    case socket.assigns.current_change do
      nil ->
        {:noreply, put_flash(socket, :error, "That provider proposal is no longer current.")}

      change ->
        result = decision_call(socket, action, change, params)

        case result do
          {:ok, _decision} ->
            {:noreply,
             socket
             |> refresh()
             |> put_flash(:info, decision_success(action))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, decision_error(reason))}
        end
    end
  end

  defp decision_call(socket, action, change, params) do
    arguments = [
      socket.assigns.current_scope,
      change.provider_reservation_change_id,
      params["proposal_hash"],
      params["reason"]
    ]

    apply(ProviderChangeApprovals, action, arguments)
  end

  defp refresh(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    {:ok, reservation} =
      ProviderReservations.fetch(
        scope.organization_id,
        mission.mission_id,
        socket.assigns.provider_reservation_id
      )

    changes =
      ProviderReservationChanges.list_for_reservation(
        scope.organization_id,
        reservation.provider_reservation_id
      )

    audit_entries =
      ProviderAudit.list_entries(scope.organization_id,
        mission_id: mission.mission_id,
        provider_reservation_id: reservation.provider_reservation_id,
        limit: 200
      )
      |> Enum.reverse()

    scheduled_contact = fetch_scheduled_contact(reservation)
    realized_contact = fetch_realized_contact(reservation, scheduled_contact)

    current_change =
      changes |> Enum.reverse() |> Enum.find(&(&1.lifecycle_state in @decision_states))

    provider = fetch_provider(reservation)
    provider_account_version = fetch_provider_account_version(reservation)
    provider_grant = fetch_provider_grant(reservation)

    socket
    |> assign(:reservation, reservation)
    |> assign(:scheduled_contact, scheduled_contact)
    |> assign(:realized_contact, realized_contact)
    |> assign(:scheduled_contact_revisions, scheduled_revisions(reservation))
    |> assign(:provider, provider)
    |> assign(:provider_account_version, provider_account_version)
    |> assign(:provider_grant, provider_grant)
    |> assign(:delivery_policy_version, delivery_policy_version(provider, current_change))
    |> assign(:admin?, organization_admin?(scope))
    |> assign(:current_change, current_change)
    |> assign_decision_forms(current_change)
    |> assign(:value_rows, value_rows(reservation, scheduled_contact, realized_contact))
    |> stream(:provider_changes, changes, reset: true)
    |> stream(:provider_audit_entries, audit_entries, reset: true)
  end

  defp assign_decision_forms(socket, nil) do
    socket
    |> assign(:approval_form, nil)
    |> assign(:rejection_form, nil)
    |> assign(:acknowledgment_form, nil)
  end

  defp assign_decision_forms(socket, change) do
    params = %{"proposal_hash" => change.proposal_hash, "reason" => ""}

    socket
    |> assign(:approval_form, to_form(params, as: :approval))
    |> assign(:rejection_form, to_form(params, as: :rejection))
    |> assign(:acknowledgment_form, to_form(params, as: :acknowledgment))
  end

  defp fetch_scheduled_contact(reservation) do
    case Cadence.Contacts.fetch_scheduled_contact(
           reservation.organization_id,
           reservation.mission_id,
           reservation.scheduled_contact_id
         ) do
      {:ok, contact} -> contact
      {:error, :scheduled_contact_not_found} -> nil
    end
  end

  defp fetch_realized_contact(_reservation, nil), do: nil

  defp fetch_realized_contact(reservation, scheduled_contact) do
    Cadence.Contacts.list_realized_contacts(reservation.organization_id, reservation.mission_id)
    |> Enum.find(&(&1.scheduled_contact_id == scheduled_contact.scheduled_contact_id))
  end

  defp fetch_provider(reservation) do
    case MissionProviders.fetch_provider_version(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_id,
           reservation.provider_version
         ) do
      {:ok, provider} -> provider
      {:error, _reason} -> nil
    end
  end

  defp fetch_provider_account_version(%{provider_account_id: nil}), do: nil

  defp fetch_provider_account_version(reservation) do
    case ProviderAccounts.fetch_version(
           reservation.organization_id,
           reservation.provider_account_id,
           reservation.provider_account_version
         ) do
      {:ok, version} -> version
      {:error, _reason} -> nil
    end
  end

  defp fetch_provider_grant(%{provider_account_grant_id: nil}), do: nil

  defp fetch_provider_grant(reservation) do
    case ProviderAccountGrants.fetch_version(
           reservation.organization_id,
           reservation.provider_account_grant_id,
           reservation.mission_id,
           reservation.provider_account_grant_version
         ) do
      {:ok, grant} -> grant
      {:error, _reason} -> nil
    end
  end

  defp scheduled_revisions(reservation) do
    ScheduledContactRevisions.list(reservation.organization_id, reservation.scheduled_contact_id)
  end

  defp delivery_policy_version(_provider, change) when not is_nil(change),
    do: change.policy_version

  defp delivery_policy_version(nil, _change), do: 1

  defp delivery_policy_version(provider, _change) do
    case DeliveryPolicy.normalize(provider.delivery_policy_document) do
      {:ok, policy} -> policy.version
      {:error, _reason} -> "invalid"
    end
  end

  defp value_rows(reservation, scheduled_contact, realized_contact) do
    requested = reservation.requested_snapshot_document
    confirmed = reservation.provider_confirmed_snapshot_document
    accepted = reservation.cadence_accepted_snapshot_document
    actual = actual_snapshot(reservation, scheduled_contact, realized_contact)

    [
      value_row("starts-at", "Start", "starts_at", requested, confirmed, accepted, actual),
      value_row("ends-at", "End", "ends_at", requested, confirmed, accepted, actual),
      value_row(
        "station",
        "Station",
        "ground_station_ref",
        requested,
        confirmed,
        accepted,
        actual
      ),
      value_row(
        "resource",
        "Antenna / pool",
        "antenna_or_service_pool_ref",
        requested,
        confirmed,
        accepted,
        actual
      ),
      value_row("status", "Contact", "status", requested, confirmed, accepted, actual)
    ]
  end

  defp value_row(id, label, key, requested, confirmed, accepted, actual) do
    %{
      id: id,
      label: label,
      requested: display_value(requested[key]),
      confirmed: display_value(confirmed[key]),
      accepted: display_value(accepted[key]),
      actual: display_value(actual[key])
    }
  end

  defp actual_snapshot(reservation, nil, _realized_contact) do
    %{
      "starts_at" => nil,
      "ends_at" => nil,
      "ground_station_ref" => nil,
      "antenna_or_service_pool_ref" => nil,
      "status" => "not materialized / #{reservation.lifecycle_state}"
    }
  end

  defp actual_snapshot(reservation, scheduled_contact, realized_contact) do
    provider_execution = scheduled_contact.metadata["provider_execution"] || %{}

    %{
      "starts_at" => DateTime.to_iso8601(scheduled_contact.starts_at),
      "ends_at" => scheduled_contact.ends_at && DateTime.to_iso8601(scheduled_contact.ends_at),
      "ground_station_ref" =>
        provider_execution["ground_station_ref"] ||
          reservation.cadence_accepted_snapshot_document["ground_station_ref"],
      "antenna_or_service_pool_ref" =>
        provider_execution["antenna_or_service_pool_ref"] ||
          reservation.cadence_accepted_snapshot_document["antenna_or_service_pool_ref"],
      "status" =>
        if(realized_contact,
          do: "#{realized_contact.lifecycle_state} / #{scheduled_contact.lifecycle_state}",
          else: Atom.to_string(scheduled_contact.lifecycle_state)
        )
    }
  end

  defp display_value(nil), do: "—"
  defp display_value(""), do: "—"
  defp display_value(value) when is_atom(value), do: Atom.to_string(value)
  defp display_value(value), do: to_string(value)

  defp organization_admin?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end

  defp active_change?(change, current_change, state) do
    not is_nil(current_change) and
      change.provider_reservation_change_id == current_change.provider_reservation_change_id and
      change.lifecycle_state == state
  end

  defp changed_field_names(change),
    do: change.changed_fields_document |> Map.keys() |> Enum.sort()

  defp classification_title(:observation), do: "Operational observation"
  defp classification_title(:policy_accept), do: "Accepted by mission policy"
  defp classification_title(:approval_required), do: "Operator approval required"
  defp classification_title(:acknowledgment_required), do: "Provider fact requires acknowledgment"
  defp classification_title(:configuration_failure), do: "Configuration conflict"

  defp change_explanation(change) do
    case change.decision_document["reasons"] do
      reasons when is_list(reasons) and reasons != [] -> Enum.join(reasons, " · ")
      _other -> "Provider revision classified without additional explanation."
    end
  end

  defp decision_label(nil), do: "none"
  defp decision_label(change), do: change.lifecycle_state

  defp schedule_revision(nil), do: "—"
  defp schedule_revision(contact), do: contact.current_revision

  defp contact_lifecycle(nil), do: "not materialized"
  defp contact_lifecycle(contact), do: contact.lifecycle_state

  defp realized_lifecycle(nil), do: "not started"
  defp realized_lifecycle(contact), do: contact.lifecycle_state

  defp account_label(nil, reservation) do
    if reservation.provider_account_id,
      do: versioned(reservation.provider_account_id, reservation.provider_account_version),
      else: "legacy / unbound"
  end

  defp account_label(version, _reservation),
    do: versioned(version.provider_account_id, version.version)

  defp grant_label(nil, reservation) do
    if reservation.provider_account_grant_id,
      do:
        versioned(
          reservation.provider_account_grant_id,
          reservation.provider_account_grant_version
        ),
      else: "legacy / unbound"
  end

  defp grant_label(grant, _reservation),
    do: "#{versioned(grant.provider_account_grant_id, grant.version)} / #{grant.lifecycle_state}"

  defp versioned(id, version), do: "#{id}:v#{version || "—"}"
  defp profile_label(ref), do: versioned(ref["id"], ref["version"])

  defp descriptor_value(reservation, key),
    do: display_value(reservation.delivery_descriptor_document[key])

  defp framing_label(reservation) do
    framing = reservation.delivery_descriptor_document["framing"] || %{}
    family = framing["family"] || "not observed"
    bytes = framing["frame_bytes"]
    if bytes, do: "#{family} / #{bytes} bytes", else: family
  end

  defp credential_label(nil), do: "legacy / unavailable"

  defp credential_label(version),
    do: "#{version.credential_ref} / account config v#{version.version}"

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
  defp format_time(value), do: display_value(value)

  defp short_hash(nil), do: "unavailable"
  defp short_hash(hash) when byte_size(hash) > 12, do: binary_part(hash, 0, 12) <> "…"
  defp short_hash(hash), do: hash

  defp state_class(state) when state in [:confirmed, :active, :completed],
    do: "border-success/40 bg-success/10 text-success"

  defp state_class(state) when state in [:failed, :rejected, :canceled],
    do: "border-error/40 bg-error/10 text-error"

  defp state_class(_state), do: "border-warning/40 bg-warning/10 text-warning"

  defp decision_success(:approve), do: "Provider revision approved and applied."
  defp decision_success(:reject), do: "Provider proposal rejected."
  defp decision_success(:acknowledge), do: "Provider fact acknowledged with contingency note."

  defp decision_error(:stale_provider_change_proposal),
    do: "The provider proposal changed. Review the current revision before deciding."

  defp decision_error(:provider_change_decision_deadline_passed),
    do: "The provider decision deadline has passed. Reconcile authoritative state."

  defp decision_error({:provider_change_not_decidable, _state}),
    do: "That provider change is no longer awaiting this decision."

  defp decision_error(_reason),
    do: "The decision could not be recorded. Current provider and Cadence state were preserved."
end
