defmodule Cadence.Architecture.PlaneAndContextBoundaryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Architecture.{ContextBoundary, DependencyBoundary, PlaneBoundary}

  test "every current core module has explicit plane and context ownership" do
    paths = ["lib/cadence.ex" | Path.wildcard("lib/cadence/**/*.ex")]

    assert [] == Enum.reject(paths, &PlaneBoundary.classify/1)

    assert [] ==
             Enum.reject(paths, fn path ->
               path == "lib/cadence.ex" or ContextBoundary.classify(path)
             end)
  end

  test "web production modules are classified as adapters" do
    assert :adapter ==
             PlaneBoundary.classify("lib/cadence_web/controllers/telemetry_controller.ex")

    assert :adapter ==
             PlaneBoundary.classify("lib/cadence_web/live/ops_dashboard_show_live.ex")
  end

  test "unclassified core modules fail closed" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence/unowned_feature/worker.ex" => %{}
      })

    assert Enum.map(findings, & &1.kind) == [:unclassified_context, :unclassified_plane]
  end

  test "enforces the context matrix while preserving named orchestration" do
    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/accounts.ex",
               "lib/cadence/catalog.ex",
               "runtime"
             )

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/catalog.ex",
               "lib/cadence/accounts.ex",
               "runtime"
             )

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/control/activations.ex",
               "lib/cadence/control/mission_runtime_reconciler.ex",
               "runtime"
             )
  end

  test "web code reaches legacy catch-all namespaces only through resource adapters" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence_web/controllers/command_request_controller.ex" => %{
          "lib/cadence_web/control_plane_params/commanding.ex" => "runtime"
        },
        "lib/cadence_web/api/commanding_params.ex" => %{
          "lib/cadence_web/control_plane_params/commanding.ex" => "runtime"
        }
      })

    assert [
             %{
               kind: :web_catch_all,
               source: "lib/cadence_web/controllers/command_request_controller.ex",
               sink: "lib/cadence_web/control_plane_params/commanding.ex"
             }
           ] = findings
  end
end
