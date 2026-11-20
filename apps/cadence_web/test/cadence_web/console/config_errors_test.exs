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

  # mms-ux (for ca-ux): a submit under 'needs a second person's approval' was Request review, so
  # the four server-worded refusals open with that act; the rest of each sentence is unchanged.
  test "the four MM&S submit refusals name the act: Request review or Apply" do
    refusals = [
      {{:mission_model_revision_not_approved, ["model_1"]},
       "a catalog revision isn't approved yet."},
      {{:mission_model_comparison_failed, "model_1", "report_1"},
       "a catalog revision's comparison didn't pass."},
      {:telemetry_app_not_installed, "the telemetry app isn't installed."},
      {:telemetry_packet_inputs_required, "telemetry's packet inputs aren't set up."}
    ]

    for {reason, rest} <- refusals,
        {act, opener} <- [{:request_review, "Not sent for review: "}, {:apply, "Not applied: "}] do
      conn = build_conn() |> Plug.Conn.assign(:submit_act, act) |> ConfigJSON.error(reason)
      assert json_response(conn, 409)["error"]["message"] == opener <> rest
    end

    # With no submit act (another route), the line stays "Not applied:".
    conn = ConfigJSON.error(build_conn(), {:mission_model_revision_not_approved, ["model_1"]})
    assert json_response(conn, 409)["error"]["message"] =~ "Not applied: "
  end

  # ca-ux (U95): an approve applies, so the four refusals take U95's form there. Without a mission
  # scope the craft is named by its id and a revision reads "a catalog revision".
  test "the four MM&S refusals on an approve are U95's: nothing applied, approval not recorded" do
    approve = fn reason ->
      build_conn()
      |> Plug.Conn.put_private(:phoenix_action, :review)
      |> ConfigJSON.error(reason)
      |> json_response(409)
      |> get_in(["error", "message"])
    end

    tail =
      ", so nothing was applied and the change set stays in review. Your approval wasn't recorded. "

    assert approve.({:telemetry_app_not_installed, ["EARENDIL-312"]}) ==
             "Not approved: the telemetry app isn't installed on EARENDIL-312" <>
               tail <> "Approve it again once the app is installed in Setup › Apps."

    assert approve.({:telemetry_packet_inputs_required, ["EARENDIL-312"]}) ==
             "Not approved: telemetry can't be turned on for EARENDIL-312 until its packet inputs are set up" <>
               tail <> "Approve it again once they're set up, or send it back."

    assert approve.({:mission_model_revision_not_approved, ["model_1"]}) ==
             "Not approved: a catalog revision isn't approved yet" <>
               tail <> "Approve it again once that catalog revision is approved."

    assert approve.({:mission_model_revision_not_approved, ["model_1", "model_2"]}) ==
             "Not approved: 2 catalog revisions aren't approved yet" <>
               tail <> "Approve it again once they're approved."

    assert approve.({:mission_model_comparison_failed, "model_1", "report_1"}) ==
             "Not approved: a catalog revision's comparison didn't pass" <>
               tail <>
               "Send it back so the author can stage a catalog revision whose comparison passed."
  end

  test "U65: the model gate's apply refusals are coded 409s named by catalog revision" do
    conn = ConfigJSON.error(build_conn(), {:mission_model_revision_not_approved, ["model_1"]})

    assert %{
             "error" => %{
               "code" => "mission_model_revision_not_approved",
               "message" => "Not applied: a catalog revision isn't approved yet.",
               "details" => %{
                 "mission_model_revision_ids" => ["model_1"],
                 "catalog_revision_numbers" => [nil]
               }
             }
           } = json_response(conn, 409)

    conn =
      ConfigJSON.error(build_conn(), {:mission_model_comparison_failed, "model_1", "report_1"})

    assert %{
             "error" => %{
               "code" => "mission_model_comparison_failed",
               "details" => %{"comparison_report_id" => "report_1"}
             }
           } = json_response(conn, 409)

    alias Cadence.Reads.ModelApplyRefusals, as: Words

    assert Words.sentence(:mission_model_revision_not_approved, [4]) ==
             "Not applied: catalog rev 4 isn't approved yet."

    assert Words.sentence(:mission_model_revision_not_approved, [4, 5]) ==
             "Not applied: catalog revs 4 and 5 aren't approved yet."

    assert Words.sentence(:mission_model_comparison_failed, [4]) ==
             "Not applied: catalog rev 4's comparison didn't pass."
  end
end
