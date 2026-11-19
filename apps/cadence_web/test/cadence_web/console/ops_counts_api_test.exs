defmodule CadenceWeb.Console.OpsCountsAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Control.MissionRuntimeStatus
  alias CadenceWeb.ControlPlaneApiFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, org: org, mission: mission}
  end

  defp counts(c, mission_id \\ nil) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/console/v1/missions/#{mission_id || c.mission.mission_id}/counts")
  end

  test "an empty mission has zero counts and null contacts", c do
    data = c |> counts() |> json_response(200) |> Map.fetch!("data")

    assert data["alarms"] == %{
             "active" => 0,
             "critical" => 0,
             "caution" => 0,
             "unacknowledged" => 0,
             "limits_configured" => false
           }

    assert data["commands"] == %{"open" => 0, "awaiting_viewer" => 0}
    assert data["fleet"] == %{"total" => 0}
    assert data["contacts"] == nil
    assert data["attention"] == %{"open" => 0, "acknowledged" => 0}
    assert data["runtime"] == nil
    assert is_binary(data["observed_at"])

    assert %{
             "total" => 0,
             "critical" => 0,
             "caution" => 0,
             "stale" => 0,
             "nominal" => 0,
             "never_heard" => 0,
             "limits_configured" => false,
             "telemetry" => "ok",
             "observed_at" => observed_at
           } = data["posture"]

    assert observed_at == data["observed_at"]
  end

  test "runtime reports a generation the runtime has failed to apply (U38)", c do
    mission_id = c.mission.mission_id
    since = DateTime.add(DateTime.utc_now(), -120, :second) |> DateTime.truncate(:second)
    on_exit(fn -> :persistent_term.erase({MissionRuntimeStatus, mission_id}) end)

    :ok =
      MissionRuntimeStatus.record(
        %{
          mission_id: mission_id,
          desired_generation: 8,
          applied_generation: 7,
          last_error: {:mission_runtime_spec_mismatch, :binding_set_content_sha256},
          failing_since: since,
          applied_at: nil
        },
        nil
      )

    runtime = c |> counts() |> json_response(200) |> get_in(["data", "runtime"])

    assert %{
             "state" => "not_applied",
             "reason" => "spec_mismatch",
             "desired_generation" => 8,
             "applied_generation" => 7
           } = runtime

    assert runtime["since"] == DateTime.to_iso8601(since)
  end

  test "counts an active alarm episode and the fleet", c do
    ControlPlaneApiFixtures.seed_mission_read_models(c.org.organization_id, c.mission.mission_id)
    data = c |> counts() |> json_response(200) |> Map.fetch!("data")

    assert %{"active" => 1, "caution" => 1, "unacknowledged" => 1, "limits_configured" => true} =
             data["alarms"]

    assert data["fleet"]["total"] == 1

    # The top bar's posture is GET /fleet's counts, by the same rule (no rows on the wire).
    fleet =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/fleet")
      |> json_response(200)
      |> Map.fetch!("data")

    posture = data["posture"]
    keys = ~w(total critical caution stale nominal never_heard)

    assert Map.take(posture, keys) == Map.take(fleet["counts"], keys)
    assert posture["limits_configured"] == fleet["limits"]["configured"]
    assert posture["telemetry"] == fleet["telemetry"]
    assert posture["total"] == 1
  end

  test "another organization's mission is not found", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert %{"error" => %{"code" => "mission_not_found"}} =
             c |> counts(stranger.mission_id) |> json_response(404)
  end
end
