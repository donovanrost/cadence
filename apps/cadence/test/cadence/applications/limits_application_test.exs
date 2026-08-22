defmodule Cadence.Applications.LimitsApplicationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    Registry
  }

  alias Cadence.Auth.Scope
  alias Cadence.Limits

  @organization_id "org-limits-application"
  @mission_id "mission-limits-application"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "limits-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "limits")

    %{scope: scope, host_context: host_context}
  end

  test "dispatches threshold definitions as immutable governed versions", context do
    request =
      request(%{
        "point_id" => "HK.bus_voltage",
        "limit_set_name" => "FLIGHT",
        "red_low" => "24.0",
        "yellow_low" => "25.5",
        "yellow_high" => "31.0",
        "red_high" => "32.5"
      })

    assert {:ok, first_definition} =
             ActionDispatcher.dispatch(context.scope, context.host_context, request)

    assert first_definition.version == 1
    assert first_definition.limit_set_name == "FLIGHT"

    assert first_definition.thresholds == %{
             "red_low" => 24.0,
             "yellow_low" => 25.5,
             "yellow_high" => 31.0,
             "red_high" => 32.5
           }

    revised_request = %ActionRequest{
      request
      | params: Map.put(request.params, "yellow_high", "30.5")
    }

    assert {:ok, revised_definition} =
             ActionDispatcher.dispatch(context.scope, context.host_context, revised_request)

    assert revised_definition.limit_definition_id == first_definition.limit_definition_id
    assert revised_definition.version == 2
    assert revised_definition.thresholds["yellow_high"] == 30.5

    assert [latest_definition] = Limits.list_limit_definitions(@mission_id)
    assert latest_definition.version == 2
  end

  test "rejects nonnumeric and inverted threshold envelopes", context do
    assert {:error,
            %ActionFailure{
              code: "invalid_number",
              field: "red_high",
              message: "Red high must be a number."
            }} =
             ActionDispatcher.dispatch(
               context.scope,
               context.host_context,
               request(%{"point_id" => "HK.invalid", "red_high" => "hot"})
             )

    assert {:error,
            %ActionFailure{
              code: "invalid_threshold_order",
              field: "red_high",
              message: "Yellow high must be lower than red high."
            }} =
             ActionDispatcher.dispatch(
               context.scope,
               context.host_context,
               request(%{
                 "point_id" => "HK.inverted",
                 "yellow_high" => "50",
                 "red_high" => "40"
               })
             )

    assert Limits.list_limit_definitions(@mission_id) == []
  end

  test "registers a mission declarative surface and host-standard status", _context do
    assert {:ok, definition} = Registry.fetch_available("limits")
    assert definition.installable_scopes == [:mission]
    assert definition.status_query_id == "cadence.limits.status"

    assert {:ok, surface} = Registry.fetch_default_surface(definition, :mission)
    assert surface.renderer == {:declarative, "cadence.host.surface.v1"}
    assert surface.actions == ["save_limit_definition"]
  end

  defp request(params) do
    %ActionRequest{
      application_key: "limits",
      application_version: 1,
      action_id: "save_limit_definition",
      params: params
    }
  end
end
