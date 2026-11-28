defmodule Cadence.Reads.ApplicationSurfaces.TrustedSurfaceContractTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

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
               %{request("telemetry_explore") | params: query}
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
                 %{request("telemetry_explore") | params: invalid}
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
               request("commands")
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
                 request("commands")
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
  end

  test "deep trusted configuration forms stay inside the output boundary", context do
    assert {:ok, _payload} =
             OpsConsole.load(
               context.scope,
               context.host_context,
               request("data_source_registration")
             )
  end

  defp request(surface_id) do
    %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id: "cadence.ops.#{surface_id}",
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
               request(surface_id)
             )

    props
  end
end
