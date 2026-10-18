defmodule Cadence.Reads.ApplicationSurfaces.Planning.FleetPolicy do
  @moduledoc "Current policy evidence and independently authorized administrative forms."

  alias Cadence.Auth
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{AutomationGrants, FleetPlanningPolicies}
  alias Cadence.Reads.ApplicationSurfaces.Planning.Form

  def load(%Scope{} = scope, mission) do
    {policy, version} = current_policy(scope, mission)
    active_version = active_policy_version(scope, mission)
    grants = AutomationGrants.list(scope.organization_id, mission.mission_id)
    active_grants = Enum.filter(grants, &(&1.lifecycle_state == :active))
    manage? = permitted?(scope, :manage_fleet_planning_policy)
    approve? = permitted?(scope, :approve_fleet_planning_policy)
    grant? = permitted?(scope, :manage_automation_grants)

    identities =
      if grant? do
        scope.organization_id
        |> Auth.list_service_identities(mission_id: mission.mission_id)
        |> Enum.filter(&(&1.lifecycle_state == :active))
      else
        []
      end

    identity_options = Enum.map(identities, &{&1.display_name, &1.service_identity_id})
    grant_options = Enum.map(active_grants, &{&1.service_identity_id, &1.automation_grant_id})

    %{
      page: policy_page_dto(mission, policy, version),
      policy_form:
        policy_form_dto(
          Form.new("policy", policy_form_params(version)),
          policy,
          manage?,
          edit_reference(scope, mission, version)
        ),
      approval_form:
        approval_form_dto(Form.new("decision", %{"reason" => ""}), policy, version, approve?),
      authorization: authorization_dto(manage? or approve? or grant?),
      grant_ledger: grant_ledger_dto(length(active_grants)),
      grant_form:
        grant_form_dto(
          Form.new("grant", grant_form_params(active_version, identities)),
          identity_options,
          active_version,
          grant?
        ),
      revocation_form:
        revocation_form_dto(
          Form.new("revocation", %{"automation_grant_id" => "", "reason" => ""}),
          grant_options,
          grant?
        ),
      automation_grants: Enum.map(grants, &automation_grant_dto/1)
    }
  end

  defp permitted?(scope, action),
    do: Policy.authorize(scope, action, %{organization_id: scope.organization_id}) == :ok

  defp current_policy(scope, mission) do
    case FleetPlanningPolicies.fetch(scope.organization_id, mission.mission_id) do
      {:ok, policy, version} -> {policy, version}
      {:error, :fleet_planning_policy_not_found} -> {nil, nil}
      {:error, _reason} -> throw(:fleet_policy_unavailable)
    end
  end

  defp active_policy_version(scope, mission) do
    case FleetPlanningPolicies.fetch_active(scope.organization_id, mission.mission_id) do
      {:ok, _policy, version} -> version
      {:error, :active_fleet_planning_policy_not_found} -> nil
      {:error, _reason} -> throw(:fleet_policy_unavailable)
    end
  end

  defp policy_page_dto(mission, policy, version) do
    %{
      policy_evidence: version && policy_evidence(version),
      back: %{
        href: "/missions/#{mission.mission_id}/ops/planning",
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

  defp policy_form_dto(_form, _policy, false, _reference), do: nil

  defp policy_form_dto(form, policy, true, reference) do
    %{
      edit_reference: reference,
      panel_id: "fleet-policy-editor",
      id: "fleet-policy-form",
      open: is_nil(policy),
      summary: if(policy, do: "Draft a new immutable version", else: "Create the initial policy"),
      fields: %{
        max_horizon_duration:
          Form.field(
            form,
            :max_horizon_duration,
            "policy-max-horizon-duration",
            "Maximum horizon",
            "text",
            required: true
          ),
        requirement_concurrency:
          Form.field(
            form,
            :requirement_concurrency,
            "policy-requirement-concurrency",
            "Requirement workers",
            "number",
            required: true,
            min: 1
          ),
        provider_search_concurrency:
          Form.field(
            form,
            :provider_search_concurrency,
            "policy-provider-concurrency",
            "Provider workers",
            "number",
            required: true,
            min: 1
          ),
        reuse_freshness_seconds:
          Form.field(
            form,
            :reuse_freshness_seconds,
            "policy-reuse-seconds",
            "Reuse seconds",
            "number",
            required: true,
            min: 0
          ),
        max_contacts:
          Form.field(
            form,
            :max_contacts,
            "policy-max-contacts",
            "Contact ceiling (optional)",
            "number",
            min: 1
          ),
        max_estimated_cost_micros:
          Form.field(
            form,
            :max_estimated_cost_micros,
            "policy-max-cost",
            "Cost micros (optional)",
            "number",
            min: 0
          ),
        currency: Form.field(form, :currency, "policy-currency", "Currency", "text"),
        critical_contact_reserve:
          Form.field(
            form,
            :critical_contact_reserve,
            "policy-critical-reserve",
            "Critical reserve",
            "number",
            required: true,
            min: 0
          ),
        automation_mode:
          Form.field(
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
          Form.field(
            form,
            :execution_concurrency,
            "policy-execution-concurrency",
            "Execution workers",
            "number",
            required: true,
            min: 1
          ),
        max_repair_attempts:
          Form.field(
            form,
            :max_repair_attempts,
            "policy-repair-attempts",
            "Repair attempts",
            "number",
            required: true,
            min: 0
          ),
        repair_horizon_duration:
          Form.field(
            form,
            :repair_horizon_duration,
            "policy-repair-horizon-duration",
            "Repair horizon",
            "text",
            required: true
          ),
        automatic_submission:
          Form.checkbox(
            form,
            :automatic_submission,
            "policy-automatic-submission",
            "Allow exact candidate Plans to be submitted automatically"
          ),
        distinct_provider_required:
          Form.checkbox(
            form,
            :distinct_provider_required,
            "policy-distinct-provider",
            "Distinct providers"
          ),
        distinct_station_required:
          Form.checkbox(
            form,
            :distinct_station_required,
            "policy-distinct-station",
            "Distinct stations"
          ),
        distinct_service_pool_required:
          Form.checkbox(
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
        policy_evidence: policy_evidence(version),
        reason:
          Form.field(
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

  defp grant_form_dto(form, options, active_version, true) do
    %{
      panel_id: "automation-grant-issuer",
      id: "automation-grant-form",
      policy_evidence: policy_evidence(active_version),
      fields: %{
        service_identity_id:
          Form.field(
            form,
            :service_identity_id,
            "grant-service-identity",
            "Mission service identity",
            "select",
            required: true,
            options: Form.options(options)
          ),
        maximum_horizon_duration:
          Form.field(
            form,
            :maximum_horizon_duration,
            "grant-max-horizon-duration",
            "Maximum horizon",
            "text",
            required: true
          ),
        maximum_contacts:
          Form.field(
            form,
            :maximum_contacts,
            "grant-max-contacts",
            "Maximum contacts",
            "number",
            required: true,
            min: 1
          ),
        maximum_execution_concurrency:
          Form.field(
            form,
            :maximum_execution_concurrency,
            "grant-execution-concurrency",
            "Execution workers",
            "number",
            required: true,
            min: 1
          ),
        valid_days:
          Form.field(
            form,
            :valid_days,
            "grant-valid-days",
            "Valid days",
            "number",
            required: true,
            min: 1
          ),
        approval_reason:
          Form.field(
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
          Form.field(
            form,
            :automation_grant_id,
            "revoke-automation-grant-id",
            "Active grant",
            "select",
            required: true,
            options: Form.options(options)
          ),
        reason:
          Form.field(
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

  defp automation_grant_dto(grant) do
    %{
      __dom_id: "automation-grant-#{grant.automation_grant_id}",
      automation_grant_id: grant.automation_grant_id,
      service_identity_id: grant.service_identity_id,
      lifecycle_state: Atom.to_string(grant.lifecycle_state),
      lifecycle_state_class: grant_state_class(grant.lifecycle_state),
      policy_evidence:
        "policy v#{grant.fleet_planning_policy_version} · #{Enum.map_join(grant.allowed_actions, ", ", &Atom.to_string/1)}",
      boundary:
        "≤ #{grant.maximum_contacts} contacts · ≤ #{hours(grant.maximum_horizon_seconds)}",
      expiry: "expires #{format_time(grant.valid_until)}"
    }
  end

  defp policy_form_params(nil) do
    %{
      "max_horizon_duration" => "24h",
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
      "repair_horizon_duration" => "24h",
      "automatic_submission" => "false",
      "distinct_provider_required" => "false",
      "distinct_station_required" => "false",
      "distinct_service_pool_required" => "false"
    }
  end

  defp policy_form_params(version) do
    %{
      "max_horizon_duration" => duration_value(version.horizon_document["max_horizon_seconds"]),
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
      "repair_horizon_duration" =>
        duration_value(version.automation_repair_document["repair_horizon_seconds"]),
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
      "maximum_horizon_duration" =>
        policy.horizon_document
        |> Map.get("max_horizon_seconds", 86_400)
        |> duration_value(),
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

  defp to_form_string(nil), do: ""

  defp to_form_string(value), do: to_string(value)

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

  defp policy_evidence(version) do
    %{
      contract_version: 1,
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      policy_id: version.fleet_planning_policy_id,
      policy_version: version.version,
      content_sha256: version.content_sha256
    }
  end

  # Do not silently floor a domain boundary stored in seconds when displaying hours.
  defp edit_reference(scope, mission, version) do
    %{
      contract_version: 1,
      organization_id: scope.organization_id,
      mission_id: mission.mission_id,
      base: version && policy_evidence(version)
    }
  end

  defp duration_value(seconds) do
    {parts, 0} =
      Enum.map_reduce([{86_400, "d"}, {3_600, "h"}, {60, "m"}, {1, "s"}], seconds, fn {unit,
                                                                                       label},
                                                                                      remaining ->
        amount = div(remaining, unit)
        {if(amount > 0, do: "#{amount}#{label}", else: nil), rem(remaining, unit)}
      end)

    parts |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  defp hours(seconds) when rem(seconds, 3_600) == 0, do: "#{div(seconds, 3_600)} h"
  defp hours(seconds), do: "#{seconds} sec"
end
