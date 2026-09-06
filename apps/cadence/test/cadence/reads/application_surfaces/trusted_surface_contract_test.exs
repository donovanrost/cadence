defmodule Cadence.Reads.ApplicationSurfaces.TrustedSurfaceContractTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.{Comms, CommsProviders, OpsConsole}

  @organization_id "org-trusted-surface-contract"
  @mission_id "mission-trusted-surface-contract"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "trusted-surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope, host_context: HostContext.mission(@mission_id)}
  end

  test "Ops telemetry output satisfies the real remote mount contract", context do
    assert {:ok,
            %{
              "data" => %{
                "presentation" => %{
                  "component" => "OpsTelemetryExplore",
                  "props" => props
                }
              }
            }} =
             OpsConsole.load(
               context.scope,
               context.host_context,
               request("ops_console", "telemetry_explore")
             )

    assert Map.has_key?(props["filter_form"], "values")

    assert Map.keys(props["filter_form"]["fields"]) |> Enum.sort() ==
             ~w(data_source_id from limit logical_source order point_id realm selection_view source_binding_id spacecraft_id time_mode to validity_state)

    assert Map.take(props["page"], [
             "heading",
             "selected_sample_state",
             "source_state",
             "time_mode"
           ]) == %{
             "heading" => "Telemetry Explore",
             "selected_sample_state" => "none",
             "source_state" => "none",
             "time_mode" => "latest"
           }

    assert props["source_context"]["actions"] == []
  end

  test "Ops route outputs satisfy their real remote mount contracts", context do
    alarms = surface_props(context, "alarms", "OpsAlarms")
    assert Map.has_key?(alarms["page"], "conditions_id")

    assert Map.keys(alarms["filters"]["fields"]) |> Enum.sort() ==
             ~w(query severity spacecraft_id state)

    timeline = surface_props(context, "timeline", "OpsTimeline")
    assert Map.has_key?(timeline["presentation"], "container")
    assert Map.has_key?(timeline["presentation"]["body"], "timeline")
    assert Map.has_key?(timeline["presentation"]["body"], "detail")

    commands = surface_props(context, "commands", "OpsCommands")
    assert Map.has_key?(commands["page"], "rows_id")
    assert Map.keys(commands["filters"]["fields"]) |> Enum.sort() == ~w(query status target)

    activations = surface_props(context, "activation_requests", "OpsActivationRequests")
    assert Map.has_key?(activations["page"], "list")

    assert Map.keys(activations["form"]) |> Enum.sort() ==
             ~w(actions id panel_id reason request_id)

    planning = surface_props(context, "fleet_planning", "OpsFleetPlanning")
    assert Map.keys(planning["actions"]) |> Enum.sort() == ~w(new_run policy refresh)
    assert Map.has_key?(planning["ledger"], "runs_id")
    assert Map.has_key?(planning["recurring_demand"], "action")

    requirements =
      surface_props(context, "contact_requirement_list", "OpsContactRequirementList")

    assert Map.has_key?(requirements["page"]["header"], "create_action")
    assert Map.has_key?(requirements["page"], "journey_steps")

    contacts = surface_props(context, "contact_schedule", "OpsContactSchedule")
    assert Map.has_key?(contacts["page"], "contact_ledger")

    assert Map.keys(contacts["search"]["fields"]) |> Enum.sort() ==
             ~w(ends_at route spacecraft starts_at)

    assert contacts["busy"] == %{"actions" => %{}, "keys" => []}
  end

  test "deep trusted configuration forms stay inside the output boundary", context do
    assert {:ok, _payload} =
             OpsConsole.load(
               context.scope,
               context.host_context,
               request("ops_console", "data_source_registration")
             )

    for surface_id <- ~w(transport_new ground_station_new) do
      result =
        Comms.load(
          context.scope,
          context.host_context,
          request("comms", surface_id)
        )

      assert match?({:ok, _payload}, result),
             "expected #{surface_id} to fit the trusted output boundary"
    end
  end

  test "provider creation represents an empty grant set as an actionable state", context do
    assert {:ok, %{"data" => data}} =
             CommsProviders.load(
               context.scope,
               context.host_context,
               request("comms", "provider_new")
             )

    assert data["accounts"]["empty"]
    assert data["accounts"]["selected"] == nil
    assert data["accounts"]["empty_state"]["action"]["href"] == "/provider-accounts"
    assert data["form"]["fields"]["provider_account_grant_id"]["value"] == ""
  end

  defp request(application_key, surface_id) do
    %SurfaceQueryRequest{
      application_key: application_key,
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id:
        "cadence.#{if(application_key == "ops_console", do: "ops", else: "comms")}.#{surface_id}",
      query_version: 1,
      params: %{}
    }
  end

  defp surface_props(context, surface_id, component) do
    assert {:ok,
            %{
              "data" => %{
                "presentation" => %{
                  "component" => ^component,
                  "props" => props
                }
              }
            }} =
             OpsConsole.load(
               context.scope,
               context.host_context,
               request("ops_console", surface_id)
             )

    props
  end
end
