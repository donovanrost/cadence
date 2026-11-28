defmodule Cadence.Applications.HostActionRefusalsTest do
  @moduledoc """
  The host action endpoint's dispatcher refuses the actions the host-action sweep removed: writes
  that skipped the safeguards of their only write path (the console's change sets, or the native
  data operations workflow). Pinned at `ActionDispatcher.dispatch`, the endpoint's entry, with an
  organization admin so a refusal can't come from authorization.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionDispatcher, ActionRequest, HostContext}
  alias Cadence.Auth.Scope

  @org "org-host-action-refusals"
  @mission "mission-host-action-refusals"

  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: "refusal-admin"},
      organization_membership: %{lifecycle_state: :active, role: :organization_admin}
    }

    %{scope: scope, host: HostContext.mission(@mission)}
  end

  @refused [
    {"ops_console", ~w(data_operations data_operations_manage),
     ~w(validate-request record-historical-workflow-request transition-group retry-group
        request-correction)}
  ]

  test "the dispatcher refuses every removed host action", c do
    for {app, surfaces, actions} <- @refused, surface <- surfaces, action <- actions do
      request = %ActionRequest{
        application_key: app,
        application_version: 1,
        surface_id: surface,
        surface_version: 1,
        action_id: action,
        params: %{}
      }

      assert {:error, reason} = ActionDispatcher.dispatch(c.scope, c.host, request),
             "#{app} #{surface} #{action}"

      assert reason in [
               :unsupported_application_action,
               :undeclared_application_action,
               :invalid_application_action_surface
             ],
             "#{app} #{surface} #{action}: #{inspect(reason)}"
    end
  end
end
