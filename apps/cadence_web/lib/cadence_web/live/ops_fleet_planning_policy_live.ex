defmodule CadenceWeb.OpsFleetPlanningPolicyLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{AutomationGrants, FleetPlanningPolicies}
  alias Phoenix.LiveView.JS

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
           AutomationGrants.issue(scope, mission.mission_id, attrs) do
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
        case AutomationGrants.revoke(
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
        <div id={if(@organization_admin?, do: nil, else: "fleet-policy-admin-required")} class="contents">
          <.vue
            id="ops-fleet-planning-policy-component"
            v-component="OpsFleetPlanningPolicy"
            page={policy_page_dto(@current_mission, @policy, @policy_version)}
            policy_form={policy_form_dto(@policy_form, @policy, @organization_admin?)}
            approval_form={approval_form_dto(
              @decision_form,
              @policy,
              @policy_version,
              @organization_admin?
            )}
            authorization={authorization_dto(@organization_admin?)}
            grant_ledger={grant_ledger_dto(@active_grant_count)}
            grant_form={grant_form_dto(
              @grant_form,
              @service_identity_options,
              @active_policy_version,
              @organization_admin?
            )}
            revocation_form={revocation_form_dto(
              @revocation_form,
              @active_grant_options,
              @organization_admin?
            )}
            automation_grants={@streams.automation_grants}
            v-on:validate-policy={JS.push("validate-policy")}
            v-on:save-policy={JS.push("save-policy")}
            v-on:approve-policy={JS.push("approve-policy")}
            v-on:validate-grant={JS.push("validate-grant")}
            v-on:issue-grant={JS.push("issue-grant")}
            v-on:revoke-grant={JS.push("revoke-grant")}
            v-ssr={false}
            class="contents"
          />
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp policy_page_dto(mission, policy, version) do
    %{
      back: %{
        href: ~p"/missions/#{mission.mission_id}/ops/planning",
        icon: "hero-arrow-left",
        label: "Fleet planning"
      },
      header: %{
        eyebrow: "Administrative boundary",
        title: "Fleet Policy & Automation",
        copy:
          "Operators declare mission needs. Organization administrators approve the bounded horizon, capacity, cost, repair, and unattended authority Cadence may use."
      },
      state: %{
        id: "fleet-policy-state",
        label: policy_state_label(policy),
        class: policy_state_class(policy)
      },
      manifest: policy_manifest_dto(version)
    }
  end

  defp policy_manifest_dto(nil) do
    %{
      id: "fleet-policy-manifest",
      version_label: "not configured",
      content_sha256: nil,
      sections: [],
      empty: %{
        id: "fleet-policy-empty",
        icon: "hero-adjustments-horizontal",
        title: "No scheduling boundary exists",
        copy:
          "Fleet runs and automation remain stopped until an administrator creates and approves a policy."
      }
    }
  end

  defp policy_manifest_dto(version) do
    %{
      id: "fleet-policy-manifest",
      version_label: "v#{version.version}",
      content_sha256: version.content_sha256,
      empty: nil,
      sections: [
        %{
          title: "Horizon & search",
          facts: [
            fact_dto("Maximum horizon", hours(version.horizon_document["max_horizon_seconds"])),
            fact_dto("Requirement workers", version.horizon_document["requirement_concurrency"]),
            fact_dto(
              "Provider workers",
              version.horizon_document["provider_search_concurrency"]
            ),
            fact_dto(
              "Evidence reuse",
              "#{version.horizon_document["reuse_freshness_seconds"]} sec"
            )
          ]
        },
        %{
          title: "Quota & budget",
          facts: [
            fact_dto("Contact ceiling", version.budget_quota_document["max_contacts"] || "none"),
            fact_dto("Cost ceiling", format_cost(version.budget_quota_document)),
            fact_dto(
              "Critical reserve",
              version.budget_quota_document["critical_contact_reserve"]
            ),
            fact_dto(
              "Default capacity",
              version.resource_policy_document["default_exclusive_capacity"]
            )
          ]
        },
        %{
          title: "Automation",
          facts: [
            fact_dto("Mode", humanize(version.automation_repair_document["mode"])),
            fact_dto(
              "Automatic submission",
              yes_no(version.automation_repair_document["automatic_submission"])
            ),
            fact_dto(
              "Execution workers",
              version.automation_repair_document["execution_concurrency"]
            ),
            fact_dto(
              "Repair attempts",
              version.automation_repair_document["max_repair_attempts"]
            )
          ]
        },
        %{
          title: "Redundancy",
          facts: [
            fact_dto(
              "Distinct provider",
              yes_no(version.redundancy_document["distinct_provider_required"])
            ),
            fact_dto(
              "Distinct station",
              yes_no(version.redundancy_document["distinct_station_required"])
            ),
            fact_dto(
              "Distinct pool",
              yes_no(version.redundancy_document["distinct_service_pool_required"])
            ),
            fact_dto(
              "Repair horizon",
              hours(version.automation_repair_document["repair_horizon_seconds"])
            )
          ]
        }
      ]
    }
  end

  defp fact_dto(term, value), do: %{term: term, value: to_string(value)}

  defp policy_form_dto(_form, _policy, false), do: nil

  defp policy_form_dto(form, policy, true) do
    %{
      panel_id: "fleet-policy-editor",
      id: "fleet-policy-form",
      open: is_nil(policy),
      summary:
        if(policy, do: "Draft a new immutable version", else: "Create the initial policy"),
      fields: %{
        max_horizon_hours:
          form_field_dto(
            form,
            :max_horizon_hours,
            "policy-max-horizon-hours",
            "Maximum hours",
            "number",
            required: true,
            min: 1
          ),
        requirement_concurrency:
          form_field_dto(
            form,
            :requirement_concurrency,
            "policy-requirement-concurrency",
            "Requirement workers",
            "number",
            required: true,
            min: 1
          ),
        provider_search_concurrency:
          form_field_dto(
            form,
            :provider_search_concurrency,
            "policy-provider-concurrency",
            "Provider workers",
            "number",
            required: true,
            min: 1
          ),
        reuse_freshness_seconds:
          form_field_dto(
            form,
            :reuse_freshness_seconds,
            "policy-reuse-seconds",
            "Reuse seconds",
            "number",
            required: true,
            min: 0
          ),
        max_contacts:
          form_field_dto(
            form,
            :max_contacts,
            "policy-max-contacts",
            "Contact ceiling",
            "number",
            required: true,
            min: 1
          ),
        max_estimated_cost_micros:
          form_field_dto(
            form,
            :max_estimated_cost_micros,
            "policy-max-cost",
            "Cost micros (optional)",
            "number",
            min: 0
          ),
        currency:
          form_field_dto(form, :currency, "policy-currency", "Currency", "text"),
        critical_contact_reserve:
          form_field_dto(
            form,
            :critical_contact_reserve,
            "policy-critical-reserve",
            "Critical reserve",
            "number",
            required: true,
            min: 0
          ),
        automation_mode:
          form_field_dto(
            form,
            :automation_mode,
            "policy-automation-mode",
            "Mode",
            "select",
            options: [
              %{label: "Advisory", value: "advisory"},
              %{label: "Approval required", value: "approval_required"},
              %{label: "Bounded automatic", value: "bounded_automatic"}
            ]
          ),
        execution_concurrency:
          form_field_dto(
            form,
            :execution_concurrency,
            "policy-execution-concurrency",
            "Execution workers",
            "number",
            required: true,
            min: 1
          ),
        max_repair_attempts:
          form_field_dto(
            form,
            :max_repair_attempts,
            "policy-repair-attempts",
            "Repair attempts",
            "number",
            required: true,
            min: 0
          ),
        repair_horizon_hours:
          form_field_dto(
            form,
            :repair_horizon_hours,
            "policy-repair-horizon-hours",
            "Repair hours",
            "number",
            required: true,
            min: 1
          ),
        automatic_submission:
          checkbox_field_dto(
            form,
            :automatic_submission,
            "policy-automatic-submission",
            "Allow exact candidate Plans to be submitted automatically"
          ),
        distinct_provider_required:
          checkbox_field_dto(
            form,
            :distinct_provider_required,
            "policy-distinct-provider",
            "Distinct providers"
          ),
        distinct_station_required:
          checkbox_field_dto(
            form,
            :distinct_station_required,
            "policy-distinct-station",
            "Distinct stations"
          ),
        distinct_service_pool_required:
          checkbox_field_dto(
            form,
            :distinct_service_pool_required,
            "policy-distinct-pool",
            "Distinct service pools"
          )
      },
      redundancy: %{id: "fleet-policy-redundancy-details", summary: "Redundancy constraints"},
      submit: %{
        id: "save-fleet-policy",
        label: if(policy, do: "Create draft version", else: "Create draft policy")
      }
    }
  end

  defp approval_form_dto(_form, _policy, _version, false), do: nil

  defp approval_form_dto(form, policy, version, true) do
    if approvable?(policy, version) do
      %{
        panel_id: "fleet-policy-approval",
        id: "fleet-policy-approval-form",
        reason:
          form_field_dto(
            form,
            :reason,
            "fleet-policy-approval-reason",
            "Approval reason",
            "textarea",
            required: true
          ),
        submit: %{id: "approve-fleet-policy", label: "Approve exact v#{version.version}"}
      }
    end
  end

  defp authorization_dto(organization_admin?) do
    %{
      organization_admin: organization_admin?,
      admin_required:
        if(organization_admin?,
          do: nil,
          else: %{
            copy: "Organization administrator authority is required to change policy or grants."
          }
        )
    }
  end

  defp grant_ledger_dto(active_grant_count) do
    %{
      id: "automation-grant-ledger",
      list_id: "automation-grants",
      empty: %{
        id: "automation-grants-empty",
        copy: "No automation authority issued."
      },
      active_count: active_grant_count,
      active_label: "#{active_grant_count} active"
    }
  end

  defp grant_form_dto(_form, _options, _active_version, false), do: nil
  defp grant_form_dto(_form, [], _active_version, true), do: nil
  defp grant_form_dto(_form, _options, nil, true), do: nil

  defp grant_form_dto(form, options, _active_version, true) do
    %{
      panel_id: "automation-grant-issuer",
      id: "automation-grant-form",
      fields: %{
        service_identity_id:
          form_field_dto(
            form,
            :service_identity_id,
            "grant-service-identity",
            "Mission service identity",
            "select",
            required: true,
            options: options_dto(options)
          ),
        maximum_horizon_hours:
          form_field_dto(
            form,
            :maximum_horizon_hours,
            "grant-max-horizon-hours",
            "Maximum hours",
            "number",
            required: true,
            min: 1
          ),
        maximum_contacts:
          form_field_dto(
            form,
            :maximum_contacts,
            "grant-max-contacts",
            "Maximum contacts",
            "number",
            required: true,
            min: 1
          ),
        maximum_execution_concurrency:
          form_field_dto(
            form,
            :maximum_execution_concurrency,
            "grant-execution-concurrency",
            "Execution workers",
            "number",
            required: true,
            min: 1
          ),
        valid_days:
          form_field_dto(
            form,
            :valid_days,
            "grant-valid-days",
            "Valid days",
            "number",
            required: true,
            min: 1
          ),
        approval_reason:
          form_field_dto(
            form,
            :approval_reason,
            "grant-approval-reason",
            "Why this unattended authority is appropriate",
            "textarea",
            required: true
          )
      },
      submit: %{id: "issue-automation-grant", label: "Issue exact grant"}
    }
  end

  defp revocation_form_dto(_form, _options, false), do: nil
  defp revocation_form_dto(_form, [], true), do: nil

  defp revocation_form_dto(form, options, true) do
    %{
      panel_id: "automation-grant-revoker",
      id: "automation-grant-revocation-form",
      fields: %{
        automation_grant_id:
          form_field_dto(
            form,
            :automation_grant_id,
            "revoke-automation-grant-id",
            "Active grant",
            "select",
            required: true,
            options: options_dto(options)
          ),
        reason:
          form_field_dto(
            form,
            :reason,
            "revoke-automation-grant-reason",
            "Revocation reason",
            "textarea",
            required: true
          )
      },
      submit: %{id: "revoke-automation-grant", label: "Revoke immediately"}
    }
  end

  defp form_field_dto(form, field, id, label, type, opts \\ []) do
    %{
      id: id,
      name: "#{form.name}[#{field}]",
      type: type,
      label: label,
      required: Keyword.get(opts, :required, false),
      min: Keyword.get(opts, :min),
      options: Keyword.get(opts, :options, []),
      value: string_form_value(form, field),
      errors: form_errors(form, field)
    }
  end

  defp checkbox_field_dto(form, field, id, label) do
    %{
      id: id,
      name: "#{form.name}[#{field}]",
      type: "checkbox",
      label: label,
      value: truthy?(Map.get(form.params, Atom.to_string(field))),
      errors: form_errors(form, field)
    }
  end

  defp options_dto(options) do
    Enum.map(options, fn {label, value} -> %{label: label, value: value} end)
  end

  defp string_form_value(form, field) do
    case Map.get(form.params, Atom.to_string(field)) do
      value when is_binary(value) -> value
      nil -> ""
      value -> to_string(value)
    end
  end

  defp form_errors(form, field) do
    form.errors
    |> Keyword.get_values(field)
    |> Enum.map(&format_form_error/1)
  end

  defp format_form_error({message, opts}) when is_binary(message) and is_list(opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp format_form_error(message) when is_binary(message), do: message
  defp format_form_error(error), do: inspect(error)

  defp automation_grant_dto(grant) do
    %{
      automation_grant_id: grant.automation_grant_id,
      service_identity_id: grant.service_identity_id,
      lifecycle_state: Atom.to_string(grant.lifecycle_state),
      lifecycle_state_class: grant_state_class(grant.lifecycle_state),
      policy_evidence:
        "policy v#{grant.fleet_planning_policy_version} · #{Enum.join(Enum.map(grant.allowed_actions, &Atom.to_string/1), ", ")}",
      boundary:
        "≤ #{grant.maximum_contacts} contacts · ≤ #{hours(grant.maximum_horizon_seconds)}",
      expiry: "expires #{format_time(grant.valid_until)}"
    }
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

    grants = AutomationGrants.list(scope.organization_id, mission.mission_id)
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
    |> stream(:automation_grants, Enum.map(grants, &automation_grant_dto/1), reset: true)
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
