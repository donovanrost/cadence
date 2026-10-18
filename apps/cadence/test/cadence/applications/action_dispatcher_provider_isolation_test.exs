defmodule Cadence.Applications.ActionDispatcherProviderIsolationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    HostContext
  }

  alias Cadence.Auth.Scope

  @organization_id "org-action-dispatcher-provider-isolation"
  @mission_id "mission-action-dispatcher-provider-isolation"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "action-dispatcher-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "derived_telemetry")

    %{scope: scope, host_context: host_context}
  end

  test "converts provider raises, throws, and exits to the typed action failure", context do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      action_id: "save_definition"
    }

    providers_by_outcome = [
      Cadence.TestActionProviders.Raising,
      Cadence.TestActionProviders.Throwing,
      Cadence.TestActionProviders.Exiting
    ]

    for provider <- providers_by_outcome do
      assert {:error,
              %ActionFailure{
                code: "application_action_failed",
                message: "The application could not complete this action."
              }} =
               ActionDispatcher.dispatch(context.scope, context.host_context, request, %{
                 "derived_telemetry" => provider
               })

      assert Process.alive?(self())
    end
  end

  test "converts configuration reference raises, throws, and exits to the same typed failure",
       context do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      action_id: "save_definition"
    }

    providers_by_outcome = [
      Cadence.TestActionProviders.ConfigurationRaising,
      Cadence.TestActionProviders.ConfigurationThrowing,
      Cadence.TestActionProviders.ConfigurationExiting
    ]

    for provider <- providers_by_outcome do
      assert {:error,
              %ActionFailure{
                code: "application_action_failed",
                message: "The application could not complete this action."
              }} =
               ActionDispatcher.dispatch(context.scope, context.host_context, request, %{
                 "derived_telemetry" => provider
               })

      assert Process.alive?(self())
    end
  end
end
