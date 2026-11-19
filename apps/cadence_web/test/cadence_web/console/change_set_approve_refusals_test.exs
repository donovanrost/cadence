defmodule CadenceWeb.Console.ChangeSetApproveRefusalsTest do
  @moduledoc """
  #262 at the console: an approve whose checks can't run is `503 preview_failed` (it used to be a
  500), with no cause on the wire; a blocking hold at approve is `409 holds_blocking` in approve's
  own words (ux U79, amended in #374), the preview as its details. Submit's `preview_failed` is
  503 too (it was the generic 422).
  """
  # Mutates :activation_governance application env.
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.Console.ConfigJSON
  alias CadenceWeb.TestFixtures

  @approve_preview_failed "Not approved: Cadence couldn't run the checks, so nothing was applied " <>
                            "and the change set stays in review. Your approval wasn't recorded. " <>
                            "Try again; if it keeps happening, tell the team that runs Cadence " <>
                            "for you."

  @approve_holds_blocking "Not approved: a blocking hold stands, so nothing was applied and the " <>
                            "change set stays in review. Your approval wasn't recorded. Approve " <>
                            "it once the hold clears; the checks show it."

  setup do
    org = TestFixtures.persist_org!()
    alice = TestFixtures.persist_user!(display_name: "Alice")
    bob = TestFixtures.persist_user!(display_name: "Bob")
    TestFixtures.grant_membership!(alice, org)
    TestFixtures.grant_membership!(bob, org)
    mission = TestFixtures.persist_mission!(org)

    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    %{alice: alice, bob: bob, base: "/api/console/v1/missions/#{mission.mission_id}/config"}
  end

  test "an approve whose checks can't run is 503 preview_failed; the set stays in review", c do
    staged =
      c.alice
      |> post_as(c.base <> "/stage", %{"summary" => "Add Inuvik", "ops" => [station_op("Inuvik")]})
      |> json_response(201)
      |> Map.fetch!("data")

    set_path = "#{c.base}/change-sets/#{staged["change_set_id"]}"

    %{"state" => "in_review", "version" => version} =
      c.alice
      |> post_as(set_path <> "/submit", %{
        "reason" => "Add the Inuvik station",
        "expected_version" => staged["version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    approve = %{
      "decision" => "approve",
      "comment" => "Looks right",
      "expected_version" => version
    }

    # The preview's own transaction hits a database error (DDL is transactional: the rename lives
    # only inside this test's sandbox).
    Cadence.Repo.query!("ALTER TABLE comms_ground_stations RENAME TO comms_ground_stations_262")
    conn = post_as(c.bob, set_path <> "/review", approve)
    Cadence.Repo.query!("ALTER TABLE comms_ground_stations_262 RENAME TO comms_ground_stations")

    assert %{"error" => error} = json_response(conn, 503)
    assert error == %{"code" => "preview_failed", "message" => @approve_preview_failed}

    assert %{"state" => "in_review", "version" => ^version} =
             c.bob |> get_as(set_path) |> json_response(200) |> Map.fetch!("data")

    assert %{"state" => "applied"} =
             c.bob
             |> post_as(set_path <> "/review", approve)
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "holds_blocking at approve is in approve's words, the preview as details" do
    preview = %{verdict: :hold, checks: [%{key: "compatibility", blocking: true, items: []}]}

    conn = ConfigJSON.error(action(:review), {:holds_blocking, preview})

    assert %{
             "error" => %{
               "code" => "holds_blocking",
               "message" => @approve_holds_blocking,
               "details" => %{"checks" => [%{"blocking" => true}]}
             }
           } = json_response(conn, 409)

    # Submit keeps its own line.
    conn = ConfigJSON.error(action(:submit), {:holds_blocking, preview})
    assert json_response(conn, 409)["error"]["message"] =~ "can't apply yet"
  end

  test "submit's preview_failed is 503 in neutral words, never the cause" do
    conn = ConfigJSON.error(action(:submit), {:preview_failed, "ERROR 42P01 (undefined_table)"})

    assert %{"error" => %{"code" => "preview_failed", "message" => message} = error} =
             json_response(conn, 503)

    assert message =~ "Cadence couldn't run the checks, so nothing changed. Try again"
    assert error["details"] == nil
    refute inspect(error) =~ "42P01"
  end

  defp action(name), do: Plug.Conn.put_private(build_conn(), :phoenix_action, name)

  defp station_op(name),
    do: %{
      "kind" => "ground_station",
      "action" => "create",
      "document" => %{"display_name" => name, "region" => "Arctic"}
    }

  defp post_as(user, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)
  defp get_as(user, path), do: user |> TestFixtures.member_conn() |> get(path)
end
