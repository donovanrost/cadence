defmodule CadenceWeb.CommandHistoryReadTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.CommandHistoryFixtures, as: Evidence
  alias Cadence.CommandMonitorFixtures, as: Fixtures
  alias Cadence.Reads.CommandHistory
  alias Cadence.Repo
  alias CadenceWeb.API.CommandingParams
  alias CadenceWeb.{HostTransportTestSupport, OpsCommandHistoryPage, TestFixtures}

  @checker Path.expand(
             "../../../../frontend/modules/commanding/src/features/command-history/producer-contract-check.mjs",
             __DIR__
           )
  @route "/missions/:mission_id/ops/commands/requests/:command_request_id/history"
  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    member = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: member
      })

    c = %{org: org.organization_id, mission: mission.mission_id, user: user, scope: scope}
    request = Fixtures.request!(c, "history-request")
    queue = Fixtures.queue!(c, request)
    release = Fixtures.release!(c, request, queue, "history-release")
    Map.merge(c, %{request: request, queue: queue, release: release})
  end

  test "uncertain native release evidence is admitted by the published contract and API filter",
       c do
    assert {:ok, [lifecycle_state: :release_uncertain]} =
             CommandingParams.command_release_attempt_filters(%{
               "lifecycle_state" => "release_uncertain"
             })

    Repo.query!(
      "UPDATE command_release_attempts SET lifecycle_state = 'release_uncertain', released_at = NULL WHERE command_release_attempt_id = $1",
      ["history-release"]
    )

    assert {:ok, model} =
             CommandHistory.load(c.scope, c.mission, "history-request", %{
               "release" => "history-release"
             })

    assert model["selection"]["release"]["state"] == "release_uncertain"
    assert model["selection"]["release"]["released_at"] == nil

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!([model])],
               stderr_to_stdout: true
             )

    assert output =~ "native producer and real Vue contract passed"
  end

  test "native producer feeds the compiled Vue contribution for each matched record kind", c do
    sample = Evidence.sample!(c)
    Evidence.action!(c, "history-action", "history-request", "history-release")
    Evidence.capability!(c, "history-capability", "history-request", "history-release")

    models =
      for {kind, id} <- [
            {:telemetry_sample, sample.sample_id},
            {:transport_action_request, "history-action"},
            {:transport_capability_record, "history-capability"}
          ] do
        verifier =
          Fixtures.verifier!(c, c.request, c.release, "verifier-#{kind}", %{
            matched_record_kind: kind,
            matched_record_id: id
          })

        assert {:ok, model} =
                 CommandHistory.load(c.scope, c.mission, "history-request", %{
                   "release" => "history-release",
                   "verifier" => verifier.command_verifier_instance_id
                 })

        assert model["evidence"]["status"] == "ready"
        model
      end

    assert {:ok, unselected} = CommandHistory.load(c.scope, c.mission, "history-request")

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!(models ++ [unselected])],
               stderr_to_stdout: true
             )

    assert output =~ "native producer and real Vue contract passed"
  end

  test "authenticated read-only history route and query preserve exact resource selection", c do
    Fixtures.verifier!(c, c.request, c.release, "history-verifier")

    path =
      "/missions/#{c.mission}/ops/commands/requests/history-request/history?release=history-release&verifier=history-verifier"

    before = Repo.all(Cadence.Commanding.CommandRequestRow)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => "commanding.history",
        "mission_id" => c.mission,
        "query_params" => %{"release" => "history-release", "verifier" => "history-verifier"}
      })

    assert snapshot["ops_page"]["data"]["selection"]["verifier"]["id"] == "history-verifier"
    assert snapshot["ops_page"]["context"]["resourceId"] == "history-request"
    refute Map.has_key?(snapshot["ops_page"], "token")
    assert Repo.all(Cadence.Commanding.CommandRequestRow) == before
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path)
  end

  test "revoked access and mismatched selections replace previous data with an unavailable envelope",
       c do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: c.scope}}

    info = %{
      route: @route,
      params: %{"mission_id" => c.mission, "command_request_id" => "history-request"}
    }

    ready = OpsCommandHistoryPage.prepare(socket, info, "/history")
    assert ready.assigns.ops_page.status == "ready"

    unavailable =
      OpsCommandHistoryPage.prepare(
        ready,
        put_in(info, [:params, "release"], "foreign"),
        "/history"
      )

    assert unavailable.assigns.ops_page.status == "unavailable"
    refute Map.has_key?(unavailable.assigns.ops_page, :data)

    revoked =
      Phoenix.Component.assign(ready, :current_scope, %{c.scope | organization_membership: nil})

    denied =
      OpsCommandHistoryPage.prepare(revoked, info, "/history",
        query: fn _, _ -> flunk("Unauthorized history SQL") end
      )

    assert denied.assigns.ops_page.status == "unavailable"
    refute Map.has_key?(denied.assigns.ops_page, :data)
  end
end
