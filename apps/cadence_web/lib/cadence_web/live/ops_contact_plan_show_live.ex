defmodule CadenceWeb.OpsContactPlanShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Projections.ContactStatus
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Socket

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

    case ManagementContacts.submit_plan(
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

  def handle_event("execute-plan", %{}, socket) do
    %{current_scope: scope, current_mission: mission, plan: plan} = socket.assigns

    {:noreply,
     socket
     |> assign(:executing?, true)
     |> assign_page_dtos()
     |> start_async(:execute_contact_plan, fn ->
       ControlContacts.execute_approved_plan(scope, mission.mission_id, plan.contact_plan_id)
     end)}
  end

  @impl true
  def handle_async(:execute_contact_plan, {:ok, {:ok, _result}}, socket) do
    socket =
      socket
      |> assign(:executing?, false)
      |> assign_page_dtos()

    case load_plan(socket) do
      {:ok, socket} -> {:noreply, put_flash(socket, :info, "Plan execution projection updated.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_async(:execute_contact_plan, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:executing?, false)
     |> assign_page_dtos()
     |> put_flash(:error, action_error(reason))}
  end

  def handle_async(:execute_contact_plan, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:executing?, false)
     |> assign_page_dtos()
     |> put_flash(:error, "Execution worker stopped. Durable reservation evidence was preserved.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-plan-show-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_plan_show"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"contact_plan_id" => @contact_plan_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp decide(socket, decision, reason) do
    %{current_scope: scope, current_mission: mission, plan: plan, version: version} =
      socket.assigns

    result =
      case decision do
        :approve ->
          ControlContacts.approve_and_accept_plan(
            scope,
            mission.mission_id,
            plan.contact_plan_id,
            plan.current_version,
            version.content_sha256,
            reason
          )

        :reject ->
          ManagementContacts.reject_plan(
            scope,
            mission.mission_id,
            plan.contact_plan_id,
            plan.current_version,
            version.content_sha256,
            reason
          )
      end

    case result do
      {:ok, _approved_plan} ->
        refresh_with_flash(socket, :info, "Plan decision recorded.")

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

    with {:ok, status} <-
           ContactStatus.project(scope.organization_id, mission.mission_id, plan_id) do
      %{plan: plan, version: version} = status.requested

      requirements =
        Enum.map(version.requirement_refs_document["requirements"] || [], fn ref ->
          {:ok, requirement} =
            ManagementContacts.fetch_requirement_version(
              scope.organization_id,
              mission.mission_id,
              ref["id"],
              ref["version"]
            )

          requirement
        end)

      selected = status.requested.selected_opportunities
      approvals = status.requested.approvals
      execution_items = status.operational.execution_items
      selected_rows = Enum.map(selected, &selected_opportunity_row_dto/1)
      execution_rows = Enum.map(execution_items, &execution_item_row_dto(&1, mission.mission_id))
      approval_rows = Enum.map(approvals, &approval_row_dto/1)

      {:ok,
       socket
       |> assign(:plan, plan)
       |> assign(:version, version)
       |> assign(:requirements, requirements)
       |> assign(:contact_status, status)
       |> assign(:selected_opportunities, selected)
       |> assign(:approvals, approvals)
       |> assign(:organization_admin?, organization_admin?(scope))
       |> assign_page_dtos()
       |> stream(:selected_opportunities, selected_rows, reset: true)
       |> stream(:execution_items, execution_rows, reset: true)
       |> stream(:approvals, approval_rows, reset: true)}
    end
  end

  defp assign_page_dtos(socket) do
    socket
    |> assign(:contact_plan_show_page, page_dto(socket.assigns))
    |> assign(:contact_plan_submission_form, submission_form_dto(socket.assigns))
    |> assign(:contact_plan_admin_controls, admin_controls_dto(socket.assigns))
  end

  defp page_dto(assigns) do
    %{
      id: "ops-contact-plan-show-page",
      back_action: %{
        label: "Requirement",
        href: requirement_path(assigns.current_mission.mission_id, assigns.requirements)
      },
      header: %{
        state: %{
          label: humanize(assigns.plan.lifecycle_state),
          class: plan_state_class(assigns.plan.lifecycle_state)
        },
        version_label: "Plan v#{assigns.version.version}",
        heading: "Contact commitment manifest",
        description:
          "Exact Requirement, opportunity, provider route, policy, and expiry evidence for this commitment.",
        execute_action: execute_action_dto(assigns)
      },
      summary: %{
        id: "plan-commitment-summary",
        coverage: %{
          label:
            if(assigns.version.coverage_document["satisfied"],
              do: "Satisfied",
              else: "Shortfall recorded"
            ),
          class:
            if(assigns.version.coverage_document["satisfied"],
              do: "mt-1 text-sm font-semibold text-success",
              else: "mt-1 text-sm font-semibold text-warning"
            )
        },
        selected_count: length(assigns.selected_opportunities),
        approval_identity: approval_identity(assigns.plan),
        content_hash: %{
          id: "contact-plan-content-hash",
          value: assigns.version.content_sha256
        }
      },
      selections: %{
        id: "plan-selections",
        empty: %{
          id: "plan-selections-empty",
          message: "No opportunities selected."
        }
      },
      unsatisfied: unsatisfied_dto(assigns.version),
      policy: policy_dto(assigns.version),
      execution: %{
        id: "plan-execution-items",
        heading: "Execution ledger",
        description: "One restart-safe saga item per selected opportunity.",
        empty: %{
          id: "plan-execution-items-empty",
          message: "Execution items are created only after approval."
        }
      },
      submission: submission_dto(assigns),
      decision: decision_dto(assigns),
      approval_evidence: %{
        id: "plan-approvals",
        heading: "Approval evidence",
        empty: %{
          id: "plan-approvals-empty",
          message: "No decision recorded."
        }
      },
      rationale: %{
        heading: "Operator rationale",
        value: assigns.version.rationale,
        plan_id: assigns.plan.contact_plan_id
      }
    }
  end

  defp execute_action_dto(%{plan: %{lifecycle_state: state}} = assigns)
       when state in [:approved, :executing, :partially_reserved, :failed] do
    %{
      id: "execute-contact-plan",
      event: "execute-plan",
      payload: %{},
      label: if(assigns.executing?, do: "Executing", else: "Execute approved Plan"),
      disabled: assigns.executing?
    }
  end

  defp execute_action_dto(_assigns), do: nil

  defp unsatisfied_dto(%{unsatisfied_document: %{"clear" => true}}), do: nil

  defp unsatisfied_dto(version) do
    %{
      id: "plan-unsatisfied",
      heading: "Unsatisfied outcomes",
      requirements:
        Enum.map(version.unsatisfied_document["requirements"] || [], fn item ->
          %{
            requirement_label:
              "#{item["contact_requirement_id"]} v#{item["contact_requirement_version"]}",
            hard_failures: Enum.map(item["hard_failures"] || [], &humanize(&1["code"]))
          }
        end)
    }
  end

  defp policy_dto(version) do
    %{
      id: "plan-policy-manifest",
      summary: "Policy and route evidence",
      selections:
        Enum.map(version.policy_snapshot_document["selections"] || [], fn selection ->
          effective_policy = selection["effective_policy"] || %{}
          route_binding = selection["route_binding"] || %{}

          %{
            contact_opportunity_snapshot_id: selection["contact_opportunity_snapshot_id"],
            route_display_name: route_binding["route_display_name"],
            policy_summary:
              "Effective policy: #{humanize(effective_policy["mode"])} · automatic revision #{if effective_policy["allow_automatic_execution_revision"], do: "allowed", else: "disabled"}"
          }
        end)
    }
  end

  defp submission_dto(%{plan: %{lifecycle_state: :draft}, approvals: []}) do
    %{
      heading: "Submit for approval",
      description: "Freeze this exact version for an organization administrator to review."
    }
  end

  defp submission_dto(_assigns), do: nil

  defp decision_dto(%{plan: %{lifecycle_state: :pending_approval}} = assigns) do
    %{
      heading: "Administrator decision",
      description:
        "Approval rechecks Requirement versions, expiry, route/grant readiness, and policy narrowing.",
      admin_required:
        if(assigns.organization_admin?,
          do: nil,
          else: %{
            id: "contact-plan-admin-required",
            message: "Organization administrator approval required."
          }
        )
    }
  end

  defp decision_dto(_assigns), do: nil

  defp submission_form_dto(
         %{plan: %{lifecycle_state: :draft}, approvals: [], submit_form: form} = assigns
       ) do
    %{
      id: "contact-plan-submit-form",
      field:
        reason_field_dto(
          form,
          "contact-plan-submit-reason",
          "submission[reason]",
          "Review note"
        ),
      action: %{
        id: "submit-contact-plan",
        label: "Submit exact v#{assigns.version.version}"
      }
    }
  end

  defp submission_form_dto(_assigns), do: nil

  defp admin_controls_dto(%{
         plan: %{lifecycle_state: :pending_approval},
         organization_admin?: true,
         decision_form: form,
         version: version
       }) do
    %{
      approve_form: %{
        id: "contact-plan-approve-form",
        field:
          reason_field_dto(
            form,
            "contact-plan-approve-reason",
            "decision[reason]",
            "Approval reason"
          ),
        action: %{
          id: "approve-contact-plan",
          label: "Approve exact v#{version.version}"
        }
      },
      rejection: %{
        id: "contact-plan-rejection-disclosure",
        summary: "Reject this version",
        form: %{
          id: "contact-plan-reject-form",
          field:
            reason_field_dto(
              form,
              "contact-plan-reject-reason",
              "decision[reason]",
              "Rejection reason"
            ),
          action: %{
            id: "reject-contact-plan",
            label: "Reject and require a new version"
          }
        }
      }
    }
  end

  defp admin_controls_dto(_assigns), do: nil

  defp reason_field_dto(form, id, name, label) do
    %{
      id: id,
      name: name,
      type: "textarea",
      label: label,
      required: true,
      value: form |> Form.input_value(:reason) |> string_value()
    }
  end

  defp selected_opportunity_row_dto(snapshot) do
    %{
      contact_opportunity_snapshot_id: snapshot.contact_opportunity_snapshot_id,
      provider_display_name: snapshot.route_binding_document["provider_display_name"],
      ground_station_ref: snapshot.normalized_opportunity_document["ground_station_ref"],
      starts_at: format_time(snapshot.starts_at),
      duration: "#{DateTime.diff(snapshot.ends_at, snapshot.starts_at)} sec",
      expiry: %{
        value: format_time(snapshot.expires_at),
        class: expiry_class(snapshot.expires_at)
      }
    }
  end

  defp execution_item_row_dto(item, mission_id) do
    %{
      contact_plan_execution_item_id: item.contact_plan_execution_item_id,
      contact_opportunity_snapshot_id: item.contact_opportunity_snapshot_id,
      attempt_count: item.attempt_count,
      state: %{
        label: humanize(item.lifecycle_state),
        class: execution_state_class(item.lifecycle_state)
      },
      contact_link:
        if(item.provider_reservation_id,
          do: %{
            label: "Contact",
            href: ~p"/missions/#{mission_id}/ops/contacts/#{item.provider_reservation_id}"
          },
          else: nil
        )
    }
  end

  defp approval_row_dto(approval) do
    %{
      contact_plan_approval_id: approval.contact_plan_approval_id,
      decision: %{
        label: humanize(approval.decision),
        class:
          if(approval.decision == :approved,
            do: "text-sm font-semibold text-success",
            else: "text-sm font-semibold text-error"
          )
      },
      version_label: "v#{approval.contact_plan_version}",
      reason: approval.reason,
      actor_summary:
        "#{approval.actor_document["display_name"]} · #{format_time(approval.decided_at)}"
    }
  end

  defp requirement_path(mission_id, [requirement | _rest]),
    do: ~p"/missions/#{mission_id}/ops/requirements/#{requirement.contact_requirement_id}"

  defp requirement_path(mission_id, []), do: requirements_path(mission_id)

  defp requirements_path(%Socket{} = socket),
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
  defp string_value(nil), do: ""
  defp string_value(value) when is_binary(value), do: value
  defp string_value(value), do: to_string(value)
end
