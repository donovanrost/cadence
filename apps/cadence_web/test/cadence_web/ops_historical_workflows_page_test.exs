defmodule CadenceWeb.OpsHistoricalWorkflowsPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources.Store
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/data-operations/src/features/historical-workflows/native-producer-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    source_id = Cadence.Ids.new("history-source")
    binding_id = Cadence.Ids.new("history-binding")

    assert {:ok, _} =
             Store.persist_data_source(%DataSource{
               data_source_id: source_id,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               adapter: Cadence.Dashboards.Sources.Telemetry
             })

    assert {:ok, _} =
             Store.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               data_source_id: source_id,
               realm: :backfill,
               logical_source: :telemetry
             })

    %{
      org: org,
      user: user,
      mission: mission,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/data-operations"
    }
  end

  test "real producer and native controls record a scoped request and recover its actual result",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["status"] == "ready"
    assert original["id"] == "data-operations.history"
    [["record-request", input]] = calls = native(%{snapshot: original})
    reply = action(view, c.path, original, "record-request", input)
    op = reply["snapshot"]
    assert op["status"] == "completed"
    assert op["result"]["event_count"] == 2
    assert op["result"]["actor_id"] == c.user.user_id
    assert op["result"]["organization_id"] == c.org.organization_id
    assert op["result"]["mission_id"] == c.mission.mission_id
    rows = Cadence.Repo.all(EventRow)

    assert Enum.sort(Enum.map(rows, & &1.backfill_lifecycle_event_id)) ==
             Enum.sort(op["result"]["event_ids"])

    assert Enum.all?(rows, &(&1.reason == String.duplicate("界", 600)))
    recovered = read(view, c.path, original)["snapshot"]
    assert recovered["data"]["operation"] == op
    assert recovered["data"]["model"]["selected"]["id"] == op["result"]["group_id"]
    assert recovered["data"]["model"]["selected"]["audit"]["total"] == 2
    assert calls == native(%{snapshot: original, operation: op, after: recovered["data"]})
    browser_fixture("request", %{snapshot: original, operation: op, after: recovered["data"]})

    assert action(view, c.path, original, "record-request", input)["snapshot"]["status"] ==
             "rejected"

    assert length(Cadence.Repo.all(EventRow)) == 2

    manage_path = c.path <> "/manage?" <> URI.encode_query(%{"group" => op["result"]["group_id"]})
    {:ok, manage, _} = live(c.conn, manage_path)
    initial_manage = page(manage)
    assert initial_manage["id"] == "data-operations.history-manage"

    Enum.reduce(["approved", "started"], initial_manage, fn stage, snapshot ->
      [["transition-group", input]] = calls = native(%{snapshot: snapshot, stage: stage})

      transition =
        action(manage, manage_path, initial_manage, "transition-group", input)["snapshot"]

      assert transition["status"] == "completed"
      assert transition["result"]["event_count"] == 2
      refreshed = read(manage, manage_path, initial_manage)["snapshot"]

      assert calls ==
               native(%{
                 snapshot: snapshot,
                 stage: stage,
                 operation: transition,
                 after: refreshed["data"]
               })

      browser_fixture(stage, %{
        snapshot: snapshot,
        operation: transition,
        after: refreshed["data"]
      })

      if stage == "started" do
        assert transition["result"]["job_count"] == 2

        for id <- transition["result"]["job_ids"] do
          assert {:ok, job} = Cadence.Jobs.fetch_job(id)
          assert job.mission_id == c.mission.mission_id
        end
      end

      refreshed
    end)
  end

  test "captured reads and actions reject foreign tokens, paths, unsupported inputs and stale sequences",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    assert read(view, c.path, Map.put(original, "token", Ecto.UUID.generate())) == %{
             "ok" => false
           }

    assert read(view, c.path <> "/manage", original) == %{"ok" => false}
    input = %{"sequence" => 1, "payload" => %{"query" => %{"bindings_page" => "2"}}}
    op = action(view, c.path, original, "read-page", input)["snapshot"]
    assert op["status"] == "completed"
    assert read(view, c.path, original)["snapshot"]["data"]["model"]["bindings"]["page"] == 2
    assert action(view, c.path, original, "read-page", input)["snapshot"]["status"] == "rejected"
    bad = %{"sequence" => 2, "payload" => %{"query" => %{"organization_id" => "foreign"}}}
    assert action(view, c.path, original, "read-page", bad)["snapshot"]["status"] == "rejected"
    assert Cadence.Repo.aggregate(EventRow, :count) == 0
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, page) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp native(supplied) do
    {output, status} =
      System.cmd("node", [@renderer, Jason.encode!(supplied)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, json] = Regex.run(~r/CADENCE_HISTORY_CALLS=([^\n]+)/, output)
    Jason.decode!(json)
  end

  defp browser_fixture(name, value) do
    if directory = System.get_env("CADENCE_HISTORY_SNAPSHOT_DIR") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, name <> ".json"), Jason.encode!(value))
    end
  end
end
