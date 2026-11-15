defmodule CadenceWeb.Console.ConfigErrorsTest do
  @moduledoc "Change-set error codes for catalog generations (#65)."
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.Console.{ConfigJSON, Problem}

  test "holds_blocking carries the preview; an in-flight race names the requests" do
    preview = %{verdict: :hold, checks: [%{key: "compatibility", blocking: true, items: []}]}

    conn = ConfigJSON.error(build_conn(), {:holds_blocking, preview})

    assert %{"error" => %{"code" => "holds_blocking", "details" => %{"checks" => [check]}}} =
             json_response(conn, 409)

    assert check["blocking"] == true

    conn = ConfigJSON.error(build_conn(), {:catalog_command_in_flight, ["cmd_1", "cmd_2"]})

    assert %{
             "error" => %{
               "code" => "catalog_command_in_flight",
               "details" => %{"command_request_ids" => ["cmd_1", "cmd_2"]}
             }
           } = json_response(conn, 409)
  end

  test "an interrupted apply that didn't land is 503 apply_interrupted (qa #19)" do
    conn = ConfigJSON.error(build_conn(), :apply_interrupted)

    assert %{"error" => %{"code" => "apply_interrupted", "message" => message}} =
             json_response(conn, 503)

    assert message =~ "did not take effect"
  end

  test "an already-decided contact plan version is a coded 422 with its message (U36)" do
    assert {422, "contact_plan_version_already_decided", message} =
             Problem.describe(:contact_plan_version_already_decided)

    assert message =~ "already decided"
  end

  test "U63: the apply's telemetry refusals are coded 409s that name the spacecraft" do
    conn = ConfigJSON.error(build_conn(), {:telemetry_app_not_installed, ["sc_312"]})

    assert %{
             "error" => %{
               "code" => "telemetry_app_not_installed",
               "message" =>
                 "Not applied: the telemetry app isn't installed on sc_312. Install the app in Setup › Apps first.",
               "details" => %{"spacecraft_ids" => ["sc_312"]}
             }
           } = json_response(conn, 409)

    conn =
      ConfigJSON.error(
        build_conn(),
        {:telemetry_packet_inputs_required, ["a", "b", "c", "d"]}
      )

    assert %{"error" => %{"code" => "telemetry_packet_inputs_required", "message" => message}} =
             json_response(conn, 409)

    assert message ==
             "Not applied: telemetry can't be turned on for 4 spacecraft until their packet inputs are set up."
  end

  test "U63 sentences name up to three spacecraft in full" do
    alias Cadence.Reads.TelemetryApplyRefusals, as: Words

    assert Words.sentence(:telemetry_packet_inputs_required, ["EARENDIL-312"]) ==
             "Not applied: telemetry can't be turned on for EARENDIL-312 until its packet inputs are set up."

    assert Words.sentence(:telemetry_app_not_installed, ["A", "B", "C"]) =~
             "installed on A, B and C."

    assert Words.sentence(:telemetry_app_not_installed, ["A", "B"]) =~ "installed on A and B."
  end
end
