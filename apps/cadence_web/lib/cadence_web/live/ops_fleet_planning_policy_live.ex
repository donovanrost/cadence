defmodule CadenceWeb.OpsFleetPlanningPolicyLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{AutomationGrants, FleetPlanningPolicies}

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
            v-component="FederatedFullPageSurface"
            application_key="ops_console"
            surface_id="fleet_planning_policy"
            host_scope="mission"
            mission_id={@current_mission.mission_id}
            query_params={%{}}
            v-ssr={false}
            class="contents"
          />
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp automation_grant_dto(grant) do
    %{
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

  defp grant_state_class(:active),
    do: "font-mono text-[0.58rem] uppercase text-success"

  defp grant_state_class(_state),
    do: "font-mono text-[0.58rem] uppercase text-base-content/45"

  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %Y %H:%MZ")
  defp action_error(:forbidden), do: "Organization administrator authority is required."
  defp action_error(:automation_grant_policy_drift), do: "The policy changed; issue a new grant."
  defp action_error(:invalid_fleet_policy_form), do: "Review the policy values and try again."
  defp action_error(:invalid_automation_grant_form), do: "Complete every grant boundary."
  defp action_error(_reason), do: "The policy operation could not be completed."
end
