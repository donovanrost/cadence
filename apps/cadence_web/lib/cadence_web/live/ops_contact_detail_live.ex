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

  alias Phoenix.LiveView.JS

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
          |> assign(:page_title, "Provider reservation #{reservation.provider_reservation_id}")
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
  def handle_event(
        "approve-provider-change",
        %{"approval" => %{"proposal_hash" => proposal_hash, "reason" => reason}},
        socket
      )
      when is_binary(proposal_hash) and is_binary(reason) do
    decide(socket, :approve, %{"proposal_hash" => proposal_hash, "reason" => reason})
  end

  def handle_event(
        "reject-provider-change",
        %{"rejection" => %{"proposal_hash" => proposal_hash, "reason" => reason}},
        socket
      )
      when is_binary(proposal_hash) and is_binary(reason) do
    decide(socket, :reject, %{"proposal_hash" => proposal_hash, "reason" => reason})
  end

  def handle_event(
        "acknowledge-provider-change",
        %{"acknowledgment" => %{"proposal_hash" => proposal_hash, "reason" => reason}},
        socket
      )
      when is_binary(proposal_hash) and is_binary(reason) do
    decide(socket, :acknowledge, %{"proposal_hash" => proposal_hash, "reason" => reason})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-detail-component"
        v-component="OpsContactDetail"
        page={@contact_detail_page}
        provider_changes={@streams.provider_changes}
        provider_audit_entries={@streams.provider_audit_entries}
        v-on:approve-provider-change={JS.push("approve-provider-change")}
        v-on:reject-provider-change={JS.push("reject-provider-change")}
        v-on:acknowledge-provider-change={JS.push("acknowledge-provider-change")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp assign_page_dto(socket) do
    assign(socket, :contact_detail_page, page_dto(socket.assigns))
  end

  defp page_dto(assigns) do
    reservation = assigns.reservation

    %{
      id: "ops-contact-detail",
      navigation: %{
        id: "back-to-contact-schedule",
        label: "Contact ledger",
        href: ~p"/missions/#{assigns.current_mission.mission_id}/ops/contacts"
      },
      header: %{
        heading: "Provider reservation",
        reservation_id: reservation.provider_reservation_id,
        state: %{
          label: display_value(reservation.lifecycle_state),
          class: state_class(reservation.lifecycle_state)
        },
        facts: [
          %{label: "Provider rev", value: display_value(reservation.provider_revision)},
          %{
            label: "Schedule rev",
            value: display_value(schedule_revision(assigns.scheduled_contact))
          },
          %{label: "Decision work", value: display_value(decision_label(assigns.current_change))}
        ]
      },
      values: %{
        id: "contact-values-matrix",
        eyebrow: "Truth ledger",
        heading: "Four values, one operational record",
        copy: "Provider truth does not silently become Cadence execution truth.",
        columns: [
          "Field",
          "Requested",
          "Provider confirmed",
          "Cadence accepted",
          "Actual / projected"
        ],
        rows: assigns.value_rows
      },
      changes: %{
        id: "contact-change-control",
        eyebrow: "Provider revision control",
        heading: "Changes and decisions",
        timeline_id: "contact-change-timeline",
        empty: %{
          id: "contact-change-timeline-empty",
          copy: "No provider revisions beyond the accepted baseline."
        }
      },
      audit: %{
        eyebrow: "Evidence timeline",
        heading: "Provider audit",
        timeline_id: "contact-audit-timeline",
        empty: %{
          id: "contact-audit-timeline-empty",
          copy: "No provider audit entries recorded yet."
        }
      },
      binding_chain: %{
        id: "contact-binding-chain",
        eyebrow: "Immutable binding chain",
        heading: "Execution ownership",
        rows: [
          %{
            label: "Provider Account",
            value: account_label(assigns.provider_account_version, reservation)
          },
          %{label: "Mission grant", value: grant_label(assigns.provider_grant, reservation)},
          %{
            label: "Mission Provider",
            value: versioned(reservation.provider_id, reservation.provider_version)
          },
          %{label: "Delivery policy", value: "v#{assigns.delivery_policy_version}"},
          %{
            label: "Transport",
            value: versioned(reservation.transport_id, reservation.transport_version)
          },
          %{label: "Service Profile", value: profile_label(reservation.service_profile_ref)},
          %{label: "Delivery Profile", value: profile_label(reservation.delivery_profile_ref)}
        ]
      },
      lifecycle: %{
        eyebrow: "Independent lifecycle",
        heading: "Operational state",
        rows: [
          lifecycle_dto(
            "Provider Contact",
            reservation.provider_status || reservation.lifecycle_state
          ),
          lifecycle_dto("Provider pass", reservation.pass_phase),
          lifecycle_dto("Delivery", reservation.delivery_state),
          lifecycle_dto("Cadence schedule", contact_lifecycle(assigns.scheduled_contact)),
          lifecycle_dto("Actual contact", realized_lifecycle(assigns.realized_contact)),
          lifecycle_dto("Reservation", reservation.lifecycle_state)
        ]
      }
    }
    |> maybe_put_admin_diagnostics(assigns)
  end

  defp lifecycle_dto(label, value), do: %{label: label, value: display_value(value)}

  defp maybe_put_admin_diagnostics(page, %{admin?: false}), do: page

  defp maybe_put_admin_diagnostics(page, assigns) do
    reservation = assigns.reservation

    Map.put(page, :admin_diagnostics, %{
      id: "contact-admin-diagnostics",
      label: "Administrator diagnostics",
      rows: [
        %{label: "Protocol", value: descriptor_value(reservation, "protocol")},
        %{label: "Endpoint", value: descriptor_value(reservation, "endpoint_ref")},
        %{label: "Framing", value: framing_label(reservation)},
        %{label: "Credential ref", value: credential_label(assigns.provider_account_version)},
        %{
          label: "Provider contact",
          value: reservation.provider_contact_ref || "not assigned"
        },
        %{label: "Provider opportunity", value: reservation.provider_opportunity_ref},
        %{label: "Client reference", value: reservation.idempotency_key}
      ],
      link: provider_diagnostics_link(reservation.provider_account_id)
    })
  end

  defp provider_diagnostics_link(nil), do: nil

  defp provider_diagnostics_link(provider_account_id) do
    %{
      id: "contact-provider-ingestion-link",
      label: "Cursor and quarantine diagnostics",
      href: ~p"/provider-accounts/#{provider_account_id}"
    }
  end

  defp provider_change_rows(changes, assigns) do
    Enum.map(changes, &provider_change_row_dto(&1, assigns))
  end

  defp provider_change_row_dto(change, assigns) do
    %{
      provider_reservation_change_id: change.provider_reservation_change_id,
      from_provider_revision: display_value(change.from_provider_revision),
      provider_revision: display_value(change.provider_revision),
      lifecycle_state: display_value(change.lifecycle_state),
      classification: classification_title(change.classification),
      policy_version: display_value(change.policy_version),
      explanation: change_explanation(change),
      changed_fields: changed_field_names(change),
      deadline: deadline_dto(change.deadline_at),
      remediation: remediation_dto(change)
    }
    |> maybe_put_decision_forms(change, assigns)
  end

  defp deadline_dto(nil), do: nil

  defp deadline_dto(deadline_at) do
    %{label: "Provider decision deadline", value: format_time(deadline_at)}
  end

  defp remediation_dto(%{lifecycle_state: :configuration_failure} = change) do
    %{
      id: "configuration-remediation-#{change.provider_reservation_change_id}",
      heading: "Never approvable from Contact data",
      copy:
        "Reconcile the Mission Provider, Transport, credential, and delivery-profile configuration before retrying. Cadence has not rewritten execution."
    }
  end

  defp remediation_dto(_change), do: nil

  defp maybe_put_decision_forms(row, _change, %{admin?: false}), do: row

  defp maybe_put_decision_forms(row, change, assigns) do
    cond do
      active_change?(change, assigns.current_change, :pending_approval) ->
        Map.put(row, :decision_forms, %{
          approval:
            decision_form_dto(
              assigns.approval_form,
              :approval,
              change.provider_reservation_change_id
            ),
          rejection:
            if(change.actionable,
              do:
                decision_form_dto(
                  assigns.rejection_form,
                  :rejection,
                  change.provider_reservation_change_id
                ),
              else: nil
            ),
          acknowledgment: nil
        })

      active_change?(change, assigns.current_change, :acknowledgment_required) ->
        Map.put(row, :decision_forms, %{
          approval: nil,
          rejection: nil,
          acknowledgment:
            decision_form_dto(
              assigns.acknowledgment_form,
              :acknowledgment,
              change.provider_reservation_change_id
            )
        })

      true ->
        row
    end
  end

  defp decision_form_dto(form, kind, change_id) do
    form_name = Atom.to_string(kind)

    %{
      id: "provider-change-#{form_name}-form-#{change_id}",
      proposal_hash: %{
        id: "#{form_name}_proposal_hash",
        name: "#{form_name}[proposal_hash]",
        value: Phoenix.HTML.Form.input_value(form, :proposal_hash)
      },
      reason: %{
        id: "#{form_name}_reason",
        name: "#{form_name}[reason]",
        label: decision_reason_label(kind),
        value: Phoenix.HTML.Form.input_value(form, :reason),
        required: true
      },
      submit: %{
        id: "#{decision_event_prefix(kind)}-provider-change-#{change_id}",
        label: decision_submit_label(kind)
      }
    }
  end

  defp decision_reason_label(:approval), do: "Approval reason"
  defp decision_reason_label(:rejection), do: "Rejection reason"
  defp decision_reason_label(:acknowledgment), do: "Contingency note"

  defp decision_event_prefix(:approval), do: "approve"
  defp decision_event_prefix(:rejection), do: "reject"
  defp decision_event_prefix(:acknowledgment), do: "acknowledge"

  defp decision_submit_label(:approval), do: "Approve current revision"
  defp decision_submit_label(:rejection), do: "Reject provider proposal"
  defp decision_submit_label(:acknowledgment), do: "Acknowledge provider fact"

  defp provider_audit_row_dto(entry) do
    %{
      provider_audit_entry_id: entry.provider_audit_entry_id,
      recorded_at: format_time(entry.recorded_at),
      action: display_value(entry.action),
      outcome: display_value(entry.outcome),
      evidence_references:
        Enum.map(entry.evidence_references, fn reference ->
          %{
            provider_evidence_id: reference["provider_evidence_id"],
            content_sha256: short_hash(reference["content_sha256"])
          }
        end)
    }
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

    socket =
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
      |> assign_page_dto()

    socket
    |> stream(:provider_changes, provider_change_rows(changes, socket.assigns), reset: true)
    |> stream(
      :provider_audit_entries,
      Enum.map(audit_entries, &provider_audit_row_dto/1),
      reset: true
    )
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
