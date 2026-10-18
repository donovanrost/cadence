defmodule CadenceWeb.OpsDiagnosticsPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{DocumentCodec, Documents}
  alias Cadence.Reads.Dashboards.ExecutionDiagnostics
  alias CadenceWeb.{OpsDiagnosticsPage, TestFixtures}
  @route "/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics"
  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "diagnostics-" <> Ecto.UUID.generate()
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    params = %{"mission_id" => mission.mission_id, "dashboard_id" => document.dashboard_id}
    path = "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}/diagnostics"

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, current_scope: scope, host_path: path}
    }

    %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      document: document,
      params: params,
      path: path,
      socket: socket
    }
  end

  test "unpublished diagnostics explain publication, admit no inspection and recover on publication",
       c do
    first = prepare(c, c.socket)
    assert first.assigns.ops_page.status == "ready"
    assert first.assigns.ops_page.data.state == "publication_required"
    assert first.assigns.ops_page.data.author
    assert first.assigns.ops_diagnostics_session == nil
    {reply, _} = OpsDiagnosticsPage.action(first, "inspect", %{"sequence" => 1})
    assert reply.status == "rejected"
    invalid = prepare(c, first, Map.put(c.params, "time_mode", "invalid"))
    assert invalid.assigns.ops_page.status == "unavailable"

    for scope <- [%{c.scope | user: nil}, %{c.scope | mission_id: "foreign"}] do
      denied = prepare(c, Phoenix.Component.assign(c.socket, :current_scope, scope))
      assert denied.assigns.ops_page.status == "unavailable"
    end

    publish(c, 1)
    ready = prepare(c, first)
    assert ready.assigns.ops_page.status == "ready"
    assert ready.assigns.ops_page.data.model.document_version == 1
  end

  test "publication admission rejects unpublished, archived and unauthorized resources", c do
    assert {:error, :unavailable} = version(c, c.scope)
    publish(c, 1)
    assert {:ok, 1} = version(c, c.scope)

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"}
        ] do
      assert {:error, :unavailable} = version(c, scope)
    end

    assert {:error, :unavailable} =
             ExecutionDiagnostics.current_version(
               nil,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    :ok =
      Documents.archive(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id,
        actor_id: c.user.user_id
      )

    assert {:error, :unavailable} = version(c, c.scope)
  end

  test "authenticated host serves compiled diagnostics, retains navigation evidence and reauthorizes refresh",
       c do
    publish(c, 1)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    first = host_page(view)
    assert first["id"] == "dashboards.execution-diagnostics"
    assert first["status"] == "ready"
    path = c.path <> "?collection=frames&filter=source&mission_id=forged"
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
    selected = host_page(view)
    assert selected["token"] == first["token"]
    assert selected["data"]["model"] == first["data"]["model"]
    assert selected["context"]["missionId"] == c.mission.mission_id

    assert selected["data"]["selection"] == %{
             "collection" => "frames",
             "filter" => "source",
             "row" => nil
           }

    assert host_action(view, path, %{selected | "token" => "forged"}, 1)["ok"] == false
    assert host_action(view, c.path, selected, 1)["ok"] == false
    reply = host_action(view, path, selected, 1)
    assert reply["ok"]
    assert reply["snapshot"]["status"] == "ok"
    assert reply["snapshot"]["state"]["sequence"] == 1
    assert reply["snapshot"]["state"]["selection"] == selected["data"]["selection"]
    assert host_action(view, path, selected, 1)["snapshot"]["status"] == "rejected"

    checker =
      Path.expand(
        "../../../../frontend/modules/dashboards-and-exploration/src/features/execution-diagnostics/page-producer-check.mjs",
        __DIR__
      )

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        [
          "--no-warnings",
          checker,
          Jason.encode!([first["data"], selected["data"], reply["snapshot"]["state"]])
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    conn = TestFixtures.member_conn(c.user)
    {:ok, revoked, _} = live(conn, c.path)
    page = host_page(revoked)
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))

    render_hook(revoked, "host:ops-page", %{
      "id" => page["id"],
      "path" => c.path,
      "token" => page["token"],
      "event" => "inspect",
      "input" => %{"sequence" => 1}
    })

    assert_redirect(revoked, "/sign-in")
  end

  test "host contains unsupported diagnostics context without remote installation fallback", c do
    publish(c, 1)

    {:ok, view, _} =
      live(TestFixtures.member_conn(c.user), c.path <> "?replay_run_id=unsupported")

    assert host_page(view)["status"] == "unavailable"
    refute Map.has_key?(host_page(view), "data")
  end

  defp host_page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp host_action(view, path, page, sequence) do
    render_hook(view, "host:ops-page", %{
      "id" => page["id"],
      "path" => path,
      "token" => page["token"],
      "event" => "inspect",
      "input" => %{"sequence" => sequence}
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  test "view navigation retains evidence and tokens while rebinding the exact current path", c do
    publish(c, 1)
    first = prepare(c, c.socket)
    initial = first.assigns.ops_page
    assert initial.status == "ready"
    assert initial.data.sequence == 0
    assert initial.data.publication_changed == false

    params =
      Map.merge(c.params, %{
        "collection" => "frames",
        "row" => String.duplicate("a", 64),
        "filter" => "source"
      })

    path = c.path <> "?collection=frames&row=" <> String.duplicate("a", 64) <> "&filter=source"
    second = prepare(c, Phoenix.Component.assign(first, :host_path, path), params, path)
    page = second.assigns.ops_page
    assert page.data.model == initial.data.model
    assert page.token == initial.token

    assert page.data.selection == %{
             collection: "frames",
             row: String.duplicate("a", 64),
             filter: "source"
           }

    assert matches?(second, path, page.token)
    refute matches?(second, c.path, page.token)
    refute matches?(second, path, "forged")

    refute matches?(
             Phoenix.Component.assign(second, :current_scope, %{c.scope | user: nil}),
             path,
             page.token
           )

    back = prepare(c, Phoenix.Component.assign(second, :host_path, c.path))
    assert back.assigns.ops_page.data.model == initial.data.model
    assert back.assigns.ops_page.data.selection.collection == "plan"
  end

  test "publication changes remain visible without silently replacing the inspection", c do
    publish(c, 1)
    first = prepare(c, c.socket)

    {:ok, _} =
      Documents.update(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        %{c.document | name: "New publication"},
        expected_version: 1
      )

    publish(c, 2)
    retained = prepare(c, first)
    assert retained.assigns.ops_page.data.publication_changed
    assert retained.assigns.ops_page.data.model == first.assigns.ops_page.data.model

    {reply, refreshed} =
      OpsDiagnosticsPage.action(retained, "inspect", %{"sequence" => 1}, opts())

    assert reply.status == "ok"
    assert reply.state.model.document_version == 2
    assert reply.state.model.name == "New publication"
    refute reply.state.publication_changed
    assert refreshed.assigns.ops_page.token == first.assigns.ops_page.token
    assert refreshed.assigns.ops_page.data.sequence == 1
  end

  test "retained models from older DTO versions renew the session and cannot execute with old tokens",
       c do
    publish(c, 1)
    first = prepare(c, c.socket)
    session = first.assigns.ops_diagnostics_session
    assert session.model.version == 2

    for old_model <- [Map.put(session.model, :version, 1), Map.delete(session.model, :version)] do
      old =
        Phoenix.Component.assign(first, :ops_diagnostics_session, %{session | model: old_model})

      refute matches?(old, c.path, session.token)
      {reply, _} = OpsDiagnosticsPage.action(old, "inspect", %{"sequence" => 1}, opts())
      assert reply.status == "unavailable" and is_nil(reply.state.model)
      assert reply.state.sequence == session.sequence

      renewed = prepare(c, old)
      assert renewed.assigns.ops_page.data.model.version == 2
      assert renewed.assigns.ops_page.token != session.token
      assert renewed.assigns.ops_page.data.sequence == 0
      refute matches?(renewed, c.path, session.token)
    end
  end

  test "runtime changes rotate page identity and preserve admitted context exactly", c do
    publish(c, 1)
    first = prepare(c, c.socket)

    query = %{
      "time_mode" => "range",
      "from" => "2026-09-07T01:00:00+01:00",
      "to" => "2026-09-07T01:00:00Z",
      "realm" => "rehearsal"
    }

    params = Map.merge(c.params, query)
    path = c.path <> "?" <> URI.encode_query(query)
    second = prepare(c, Phoenix.Component.assign(first, :host_path, path), params, path)
    refute second.assigns.ops_page.token == first.assigns.ops_page.token
    assert second.assigns.ops_page.data.runtime_query == query

    assert second.assigns.ops_diagnostics_session.runtime.time_context.from ==
             ~U[2026-09-07 00:00:00Z]

    assert second.assigns.ops_page.data.sequence == 0
    refute matches?(second, path, first.assigns.ops_page.token)
  end

  test "unknown actions and stale or browser-expanded refresh commands never advance state", c do
    publish(c, 1)
    first = prepare(c, c.socket)

    for {event, input} <- [
          {"unknown", %{"sequence" => 1}},
          {"inspect", %{"sequence" => 0}},
          {"inspect", %{"sequence" => 2}},
          {"inspect", %{"sequence" => 1, "runtime" => %{}}},
          {"inspect", %{"sequence" => 1.0}}
        ] do
      assert {%{status: "rejected"}, ^first} =
               OpsDiagnosticsPage.action(first, event, input, opts())
    end

    {reply, refreshed} = OpsDiagnosticsPage.action(first, "inspect", %{"sequence" => 1}, opts())
    assert reply.status == "ok"
    assert reply.state.sequence == 1

    assert {%{status: "rejected"}, ^refreshed} =
             OpsDiagnosticsPage.action(refreshed, "inspect", %{"sequence" => 1}, opts())
  end

  test "lost authorization clears retained evidence on navigation and explicit refresh", c do
    publish(c, 1)
    first = prepare(c, c.socket)

    revoked =
      Phoenix.Component.assign(first, :current_scope, %{c.scope | organization_membership: nil})

    unavailable = prepare(c, revoked)
    assert unavailable.assigns.ops_page.status == "unavailable"
    refute Map.has_key?(unavailable.assigns.ops_page, :data)
    assert unavailable.assigns.ops_diagnostics_session == nil
    {reply, refreshed} = OpsDiagnosticsPage.action(revoked, "inspect", %{"sequence" => 1}, opts())
    assert reply.status == "unavailable"
    assert reply.state.model == nil
    refute Map.has_key?(refreshed.assigns.ops_page, :data)

    {rejected, cleared} = OpsDiagnosticsPage.action(revoked, "unknown", %{}, opts())
    assert rejected.status == "unavailable"
    assert rejected.state.model == nil
    refute Map.has_key?(cleared.assigns.ops_page, :data)
  end

  test "unsupported browser context and route exit discard the old inspection session", c do
    publish(c, 1)
    first = prepare(c, c.socket)
    bad = prepare(c, first, Map.put(c.params, "replay_run_id", "unsupported"))
    assert bad.assigns.ops_page.status == "unavailable"
    assert bad.assigns.ops_diagnostics_session == nil
    left = OpsDiagnosticsPage.prepare(first, %{route: "/other"}, "/other")
    assert left.assigns.ops_diagnostics_session == nil
  end

  defp prepare(c, socket, params \\ nil, path \\ nil),
    do:
      OpsDiagnosticsPage.prepare(
        socket,
        %{route: @route, params: params || c.params},
        path || c.path,
        opts()
      )

  # The session contract is independent of source success. Real producer execution
  # and partial inspection are covered by DashboardExecutionDiagnosticsTest.
  defp opts, do: [resolution_context: :unavailable, runtime_health: :missing_diagnostics_runtime]

  defp version(c, scope),
    do: ExecutionDiagnostics.current_version(scope, c.mission.mission_id, c.document.dashboard_id)

  defp publish(c, version),
    do:
      Documents.publish(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        version,
        expected_version: version
      )

  defp matches?(socket, path, token),
    do:
      OpsDiagnosticsPage.matches?(socket, %{
        "id" => "dashboards.execution-diagnostics",
        "path" => path,
        "token" => token
      })
end
