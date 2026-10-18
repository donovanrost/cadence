defmodule Cadence.Reads.ApplicationSurfaces.TrustedSurfaceContractTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.ActionProvider, as: OpsActionProvider
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.FleetPlanningRuns
  alias Cadence.Reads.ApplicationSurfaces.{Comms, CommsProviders, OpsConsole}

  @organization_id "org-trusted-surface-contract"
  @mission_id "mission-trusted-surface-contract"
  @exploration_checker Path.expand(
                         "../../../../../../frontend/modules/dashboards-and-exploration/src/features/exploration/producer-contract-check.mjs",
                         __DIR__
                       )

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

  test "legacy Ops telemetry delegates its exact query to the canonical exploration page",
       context do
    query = %{
      "point_id" => "HK.voltage+raw",
      "source_binding_id" => "binding/a",
      "source_dashboard_id" => "origin",
      "selection_view" => "canonical",
      "data_view" => "original",
      "sample_id" => "sample+one",
      "selected_time" => "2026-09-07T11:00:00.123456+02:00"
    }

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
               %{request("ops_console", "telemetry_explore") | params: query}
             )

    assert props == %{"mission_id" => @mission_id, "query" => query}
    empty = surface_props(context, "telemetry_explore", "OpsTelemetryExplore")
    assert empty == %{"mission_id" => @mission_id, "query" => %{}}

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @exploration_checker, Jason.encode!([empty, props]), "legacy"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Legacy exploration producer/consumer contract passed"

    for invalid <- [
          %{"unknown" => "selector"},
          %{"point_id" => ["nested"]},
          %{"point_id" => "bad\n"},
          %{"source_binding_id" => String.duplicate("x", 257)}
        ] do
      assert {:error, :unsupported_application_surface_query} =
               OpsConsole.load(
                 context.scope,
                 context.host_context,
                 %{request("ops_console", "telemetry_explore") | params: invalid}
               )
    end
  end

  test "legacy commands preserve only admitted navigation context through the real Vue adapter",
       context do
    query = %{
      "status" => "queued",
      "target" => "endpoint/a",
      "query" => "CMD+a",
      "focus_command_id" => "request/a?b",
      "page" => "2"
    }

    assert {:ok,
            %{"data" => %{"presentation" => %{"component" => "OpsCommands", "props" => props}}}} =
             OpsConsole.load(context.scope, context.host_context, %{
               request("ops_console", "commands")
               | params: query
             })

    assert props == %{"mission_id" => @mission_id, "query" => query}

    checker =
      Path.expand(
        "../../../../../../frontend/modules/commanding/src/features/mission-commands/producer-contract-check.mjs",
        __DIR__
      )

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        [
          "--no-warnings",
          checker,
          Jason.encode!([props, %{"mission_id" => @mission_id, "query" => %{}}]),
          "legacy"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Legacy command monitor producer/consumer contract passed"

    for invalid <- [
          %{"document" => %{}},
          %{"status" => "launch"},
          %{"page" => "0"},
          %{"query" => "bad\n"}
        ] do
      assert {:error, :unsupported_application_surface_query} =
               OpsConsole.load(context.scope, context.host_context, %{
                 request("ops_console", "commands")
                 | params: invalid
               })
    end
  end

  test "Ops route outputs satisfy their real remote mount contracts", context do
    alarms = surface_props(context, "alarms", "OpsAlarms")
    assert alarms == %{"mission_id" => @mission_id, "query" => %{}}

    timeline = surface_props(context, "timeline", "OpsTimeline")
    assert timeline == %{"mission_id" => @mission_id, "query" => %{}}

    commands = surface_props(context, "commands", "OpsCommands")
    assert commands == %{"mission_id" => @mission_id, "query" => %{}}

    activations =
      surface_props(
        context,
        "activation_requests",
        "OpsActivationRequests"
      )

    assert Map.has_key?(activations["page"], "list")

    assert Map.keys(activations["form"]) |> Enum.sort() ==
             ~w(actions id panel_id reason request_id)

    planning = surface_props(context, "fleet_planning", "OpsFleetPlanning")
    assert planning["directory"]["contract_version"] == 1
    assert planning["directory"]["active_policy"] == nil

    assert planning["directory"]["runs"] == %{
             "page" => 1,
             "more" => false,
             "entries" => []
           }

    requirements =
      surface_props(context, "contact_requirement_list", "OpsContactRequirementList")

    assert Map.has_key?(requirements["page"]["header"], "create_action")
    assert Map.has_key?(requirements["page"], "journey_steps")

    %{"schedule" => contacts} = surface_props(context, "contact_schedule", "OpsContactSchedule")
    assert contacts["contract_version"] == 1
    assert contacts["context"]["mission_id"] == @mission_id
    assert contacts["selected_spacecraft"] == nil
    assert contacts["routes"] == %{"page" => 1, "more" => false, "entries" => []}

    for ledger <- ~w(scheduled realized reservations),
        do: assert(contacts[ledger] == %{"page" => 1, "more" => false, "entries" => []})

    assert is_boolean(contacts["permissions"]["operate"])
    assert is_boolean(contacts["permissions"]["cancel"])
  end

  test "planning ownership entries render the current authorized surface producers", context do
    models =
      for {surface, component} <- [
            {"fleet_planning", "OpsFleetPlanning"},
            {"fleet_planning_new", "OpsFleetPlanningNew"},
            {"fleet_planning_policy", "OpsFleetPlanningPolicy"},
            {"contact_requirement_list", "OpsContactRequirementList"},
            {"contact_requirement_new", "OpsContactRequirementNew"},
            {"contact_requirement_template", "OpsContactRequirementTemplate"},
            {"contact_schedule", "OpsContactSchedule"}
          ] do
        %{component: component, props: surface_props(context, surface, component)}
      end

    checker =
      Path.expand(
        "../../../../../../frontend/modules/planning-and-contacts/src/test-support/producer-render-check.mjs",
        __DIR__
      )

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", checker, Jason.encode!(models)],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Planning ownership producer/consumer render checks passed"
  end

  test "native fleet creation carries the public producer review through the public action provider" do
    c = Cadence.FleetStartFixtures.setup_start()
    host = HostContext.mission(c.mission_id)
    query = request("ops_console", "fleet_planning_new")

    assert {:ok, %{"data" => %{"presentation" => %{"props" => %{"start" => model}}}}} =
             OpsConsole.load(c.scope, host, query)

    window = %{
      "horizon_start" => "2026-07-17T04:00:00.000Z",
      "horizon_end" => "2026-07-17T08:00:00.000Z",
      "include_recurring" => false
    }

    supplied = %{model: model, window: window}
    preview = native_fleet_payload(supplied)
    assert preview == %{"fleet_run" => window, "requirements_page" => 1, "templates_page" => 1}

    assert {:ok, %{"review" => review}} =
             fleet_action(c.scope, host, "validate-fleet-run", preview)

    assert review["window"] == window
    assert FleetPlanningRuns.list(c.organization_id, c.mission_id) == []
    creation = native_fleet_payload(Map.put(supplied, :review, review))
    assert creation == %{"fleet_run" => window, "evidence" => review["evidence"]}
    assert {:ok, receipt} = fleet_action(c.scope, host, "create-fleet-run", creation)
    assert receipt["evidence"] == review["evidence"]
    assert receipt["requirementCount"] == 1
    assert receipt["lifecycleState"] == "queued"

    assert native_fleet_payload(Map.merge(supplied, %{review: review, receipt: receipt})) ==
             creation

    assert byte_size(Jason.encode!(review)) < 60_000

    revoked = %{c.scope | organization_membership: nil}

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(revoked, host, query)

    assert {:error, :forbidden} = fleet_action(revoked, host, "create-fleet-run", creation)

    assert {:error, :scope_mismatch} =
             fleet_action(
               c.scope,
               host,
               "create-fleet-run",
               Map.put(creation, "mission_id", "foreign")
             )

    assert [_] = FleetPlanningRuns.list(c.organization_id, c.mission_id)
  end

  defp fleet_action(scope, host, action, params) do
    OpsActionProvider.execute(
      scope,
      host,
      %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        surface_id: "fleet_planning_new",
        surface_version: 1,
        action_id: action,
        params: params
      }
    )
  end

  defp native_fleet_payload(supplied) do
    checker =
      Path.expand(
        "../../../../../../frontend/modules/planning-and-contacts/src/features/fleet-planning/start-producer-check.mjs",
        __DIR__
      )

    {output, status} =
      System.cmd("node", [checker, Jason.encode!(supplied)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, payload] = Regex.run(~r/FLEET_START_PAYLOAD=([^\n]+)/, output)
    Jason.decode!(payload)
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
