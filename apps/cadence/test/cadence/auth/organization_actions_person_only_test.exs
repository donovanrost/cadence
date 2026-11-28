defmodule Cadence.Auth.OrganizationActionsPersonOnlyTest do
  @moduledoc """
  #282: organization-level actions are a person's by default. Every action that goes through
  Policy's organization capability check refuses a service identity, even one holding
  organization_admin or platform_admin, with `authenticated_user_required`. A person admin and a
  platform admin pass as before.

  Since #384 retired the bearer routes that were the only exceptions, every organization-level
  action refuses a service, and the allow-list that used to carry them is gone.
  """
  use ExUnit.Case, async: true

  alias Cadence.Auth.{Policy, Scope}

  @org "org-282"

  # Every action Policy routes through its organization capability check (policy.ex).
  @organization_actions [
    :read_organization,
    :manage_missions,
    :manage_organization_members,
    :create_missions,
    :manage_provider_accounts,
    :approve_provider_changes,
    :approve_mission_model,
    :approve_contact_plans,
    :manage_fleet_planning_policy,
    :approve_fleet_planning_policy,
    :manage_automation_grants,
    :manage_service_identities
  ]

  for action <- @organization_actions do
    describe "#{action}" do
      @action action

      test "a service holding organization_admin is refused" do
        assert Policy.authorize(service([:organization_admin]), @action, params()) ==
                 service_answer(@action)
      end

      test "a service holding platform_admin is refused the same way (the check comes first)" do
        assert Policy.authorize(service([:platform_admin]), @action, params()) ==
                 service_answer(@action)
      end

      test "the person check comes before the role and organization checks" do
        # A service with no admin role, or from another organization, gets the person refusal,
        # not forbidden or scope_mismatch (ca-security: before any membership or role lookup).
        assert Policy.authorize(service([]), @action, params()) == service_answer(@action)

        assert Policy.authorize(
                 service([:organization_admin], "org-other"),
                 @action,
                 params()
               ) == service_answer(@action)
      end

      test "a person who is the organization's admin passes" do
        assert Policy.authorize(person(@org, [:organization_admin]), @action, params()) == :ok
      end

      test "a platform admin passes, in any organization" do
        assert Policy.authorize(person("org-other", [:platform_admin]), @action, params()) == :ok
      end

      test "a person who isn't an admin, or is another organization's, is refused as before" do
        assert Policy.authorize(person(@org, []), @action, params()) == {:error, :forbidden}

        assert Policy.authorize(person("org-other", [:organization_admin]), @action, params()) ==
                 {:error, :scope_mismatch}
      end
    end
  end

  # approve_mission_model keeps its own refusal for a service (its clause comes first, #92).
  defp service_answer(:approve_mission_model),
    do: {:error, :human_mission_model_approver_required}

  defp service_answer(_action), do: {:error, :authenticated_user_required}

  defp params, do: %{organization_id: @org}

  defp service(capabilities, organization_id \\ @org) do
    %Scope{
      actor_kind: :service,
      organization_id: organization_id,
      mission_id: "mission-282",
      service_identity: %{
        service_identity_id: "svc-282",
        organization_id: @org,
        mission_id: "mission-282",
        lifecycle_state: :active
      },
      capabilities: MapSet.new(capabilities)
    }
  end

  defp person(organization_id, capabilities) do
    %Scope{
      actor_kind: :user,
      user: %{user_id: "user-282"},
      organization_id: organization_id,
      capabilities: MapSet.new(capabilities)
    }
  end
end
