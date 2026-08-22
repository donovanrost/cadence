defmodule Cadence.Applications.DerivedTelemetryApplicationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    HostContext
  }

  alias Cadence.Auth.Scope
  alias Cadence.Governance

  @organization_id "org-derived-telemetry-application"
  @mission_id "mission-derived-telemetry-application"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "derived-telemetry-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "derived_telemetry")

    %{scope: scope, host_context: host_context}
  end

  test "dispatches a declared action into governed immutable definition versions", context do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      action_id: "save_definition",
      params: %{
        "point_id" => "DERIVED.bus_power",
        "point_name" => "Bus power",
        "expression" => "HK.voltage * HK.current"
      }
    }

    assert {:ok, first_definition} =
             ActionDispatcher.dispatch(context.scope, context.host_context, request)

    assert first_definition.version == 1
    assert first_definition.point_name == "Bus power"
    assert first_definition.source_point_ids == ["HK.voltage", "HK.current"]

    revised_request = %ActionRequest{
      request
      | params: %{
          "point_id" => "DERIVED.bus_power",
          "point_name" => "Revised bus power",
          "expression" => "HK.voltage * HK.current * 0.95"
        }
    }

    assert {:ok, revised_definition} =
             ActionDispatcher.dispatch(context.scope, context.host_context, revised_request)

    assert revised_definition.derived_definition_id == first_definition.derived_definition_id
    assert revised_definition.version == 2
    assert revised_definition.point_name == "Revised bus power"

    assert [latest_definition] = Governance.list_derived_definitions(@mission_id)
    assert latest_definition.version == 2
    assert latest_definition.expression == "HK.voltage * HK.current * 0.95"
  end

  test "rejects declared actions without mission authority", context do
    unauthorized_scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "unauthorized-derived-operator"}
    }

    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      action_id: "save_definition",
      params: %{
        "point_id" => "DERIVED.unauthorized",
        "expression" => "HK.value * 2"
      }
    }

    assert {:error, :forbidden} =
             ActionDispatcher.dispatch(unauthorized_scope, context.host_context, request)

    assert Governance.list_derived_definitions(@mission_id) == []
  end

  test "returns typed field failures from the application adapter", context do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      action_id: "save_definition",
      params: %{"point_id" => "DERIVED.missing_expression", "expression" => ""}
    }

    assert {:error,
            %ActionFailure{
              code: "required_field",
              field: "expression",
              message: "Expression is required."
            }} = ActionDispatcher.dispatch(context.scope, context.host_context, request)

    assert Governance.list_derived_definitions(@mission_id) == []
  end
end
