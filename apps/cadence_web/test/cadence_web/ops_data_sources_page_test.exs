defmodule CadenceWeb.OpsDataSourcesPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources, as: Definitions
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/data-operations/src/features/data-sources/native-producer-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    %{
      org: org,
      user: user,
      mission: mission,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/data-sources"
    }
  end

  test "real producer and mounted registration controls return durable source and audit identities",
       c do
    path = c.path <> "/registration/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["status"] == "ready"
    assert original["id"] == "data-operations.source-registration"
    id = Cadence.Ids.new("native-source")
    supplied = %{snapshot: original, source_id: id}
    [["register-source", input]] = calls = native(supplied)
    op = action(view, path, original, "register-source", input)["snapshot"]
    assert op["status"] == "completed"
    assert op["result"]["source_id"] == id
    assert op["result"]["actor_id"] == c.user.user_id
    assert {:ok, source} = Definitions.fetch_data_source(id)
    assert op["result"]["event_ids"] == [source.current_event_id]
    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["data"]["operation"] == op
    assert refreshed["data"]["model"]["selected"] == nil
    fixture = Map.merge(supplied, %{operation: op, after: refreshed["data"]})
    assert native(fixture) == calls
    browser_fixture("registration", fixture)

    assert action(view, path, original, "register-source", input)["snapshot"]["status"] ==
             "rejected"

    assert length(
             Definitions.list_data_source_events(c.org.organization_id, c.mission.mission_id,
               data_source_id: id
             )
           ) == 1
  end

  test "native settings preserve reviewed source and return the actual disable event", c do
    source = source(c, "source")
    path = c.path <> "/#{source.data_source_id}/settings"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    supplied = %{snapshot: original, action: "disable-source"}
    [["disable-source", input]] = calls = native(supplied)
    op = action(view, path, original, "disable-source", input)["snapshot"]
    assert op["status"] == "completed"
    assert {:ok, updated} = Definitions.fetch_data_source(source.data_source_id)
    assert updated.status == :disabled
    assert op["result"]["event_ids"] == [updated.current_event_id]
    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["data"]["model"]["selected"]["source"]["status"] == "disabled"
    fixture = Map.merge(supplied, %{operation: op, after: refreshed["data"]})
    assert native(fixture) == calls
    browser_fixture("settings", fixture)
    stale = Map.put(input, "sequence", 2)

    assert action(view, path, original, "enable-source", stale)["snapshot"]["status"] ==
             "rejected"

    assert {:ok, %{status: :disabled}} = Definitions.fetch_data_source(source.data_source_id)
  end

  test "binding controls send exact displayed destination and reconcile the changed binding", c do
    origin = source(c, "origin")
    target = source(c, "target")

    assert {:ok, binding} =
             Definitions.persist_data_binding(%DataBinding{
               binding_id: Cadence.Ids.new("binding"),
               organization_id: c.org.organization_id,
               mission_id: c.mission.mission_id,
               data_source_id: origin.data_source_id,
               logical_source: :telemetry,
               realm: :flight
             })

    path = c.path <> "/#{origin.data_source_id}/settings?binding_id=#{binding.binding_id}"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)

    supplied = %{
      snapshot: original,
      action: "change-binding",
      binding_id: binding.binding_id,
      target_id: target.data_source_id
    }

    [["change-binding", input]] = calls = native(supplied)
    op = action(view, path, original, "change-binding", input)["snapshot"]
    assert op["status"] == "completed"
    assert {:ok, changed} = Definitions.fetch_data_binding(binding.binding_id)
    assert changed.data_source_id == target.data_source_id
    assert op["result"]["result"]["bindingVersion"] == changed.binding_version
    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["status"] == "ready"
    assert refreshed["data"]["model"]["query"]["binding_id"] == nil
    fixture = Map.merge(supplied, %{operation: op, after: refreshed["data"]})
    assert native(fixture) == calls
    browser_fixture("binding", fixture)
  end

  test "native job recovery requeues the displayed running deployment and admits its receipt",
       c do
    source = source(c, "deployment")

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :tsdb_backend_lifecycle,
               c.mission.mission_id,
               Cadence.Ids.new("run"),
               %{
                 organization_id: c.org.organization_id,
                 mission_id: c.mission.mission_id,
                 data_source_id: source.data_source_id,
                 operation: "provision"
               }
             )

    assert [_] = Cadence.Jobs.claim_jobs(1)
    path = c.path <> "/#{source.data_source_id}/settings"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    supplied = %{snapshot: original, action: "requeue-deployment-run", job_id: job.job_id}
    [["requeue-deployment-run", input]] = calls = native(supplied)
    op = action(view, path, original, "requeue-deployment-run", input)["snapshot"]
    assert op["status"] == "completed"
    assert op["result"]["result"]["jobId"] == job.job_id
    assert {:ok, %{status: :queued}} = Cadence.Jobs.fetch_job(job.job_id)
    refreshed = read(view, path, original)["snapshot"]
    fixture = Map.merge(supplied, %{operation: op, after: refreshed["data"]})
    assert native(fixture) == calls
    browser_fixture("requeue", fixture)
  end

  test "path subjects, tokens and action sequences remain captured across independent paging",
       c do
    source = source(c, "pinned")
    other = source(c, "other")
    path = c.path <> "/#{source.data_source_id}/settings?data_source_id=#{other.data_source_id}"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["data"]["model"]["selected"]["source"]["id"] == source.data_source_id
    assert read(view, path, Map.put(original, "token", Ecto.UUID.generate())) == %{"ok" => false}
    assert read(view, c.path, original) == %{"ok" => false}

    input = %{
      "sequence" => 1,
      "payload" => %{"query" => %{"data_source_id" => other.data_source_id}}
    }

    assert action(view, path, original, "read-page", input)["snapshot"]["status"] == "rejected"

    input =
      put_in(input, ["payload", "query"], %{
        "data_source_id" => source.data_source_id,
        "events_page" => "2"
      })

    assert action(view, path, original, "read-page", input)["snapshot"]["status"] == "completed"
    model = read(view, path, original)["snapshot"]["data"]["model"]
    assert model["selected"]["events"]["page"] == 2
    assert model["sources"]["page"] == 1
    assert model["selected"]["source"]["id"] == source.data_source_id
    assert action(view, path, original, "read-page", input)["snapshot"]["status"] == "rejected"
  end

  test "reader permissions and cross-mission source placement do not grant settings authority",
       c do
    source = source(c, "reader")
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, c.org, role: :member)
    conn = TestFixtures.member_conn(member)
    path = c.path <> "/#{source.data_source_id}"
    {:ok, view, _} = live(conn, path)
    original = page(view)
    assert original["data"]["model"]["permissions"]["manage"] == false

    input = %{
      "sequence" => 1,
      "payload" => %{
        "params" => %{"data-source-id" => source.data_source_id},
        "review" => %{"source" => original["data"]["model"]["selected"]["source"]["evidence"]},
        "confirmed" => true
      }
    }

    assert action(view, path, original, "disable-source", input)["snapshot"]["status"] ==
             "rejected"

    assert {:ok, %{status: :active}} = Definitions.fetch_data_source(source.data_source_id)
    foreign = TestFixtures.persist_mission!(c.org)

    {:ok, foreign_view, _} =
      live(c.conn, "/missions/#{foreign.mission_id}/ops/data-sources/#{source.data_source_id}")

    assert page(foreign_view)["status"] == "unavailable"
  end

  test "refresh and mutations recheck the authenticated session before reading or writing", c do
    source = source(c, "revoked")
    path = c.path <> "/#{source.data_source_id}/settings"

    for event <- ["host:ops-page:read", "host:ops-page"] do
      conn = TestFixtures.member_conn(c.user)
      {:ok, view, _} = live(conn, path)
      original = page(view)
      params = %{"path" => path, "id" => original["id"], "token" => original["token"]}

      params =
        if event == "host:ops-page",
          do:
            Map.merge(params, %{
              "event" => "disable-source",
              "input" => %{
                "sequence" => 1,
                "payload" => %{
                  "params" => %{"data-source-id" => source.data_source_id},
                  "review" => %{
                    "source" => original["data"]["model"]["selected"]["source"]["evidence"]
                  },
                  "confirmed" => true
                }
              }
            }),
          else: params

      :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
      render_hook(view, event, params)
      assert_redirect(view, "/sign-in")
      assert {:ok, %{status: :active}} = Definitions.fetch_data_source(source.data_source_id)
    end
  end

  defp source(c, label) do
    assert {:ok, source} =
             Definitions.persist_data_source(%DataSource{
               data_source_id: Cadence.Ids.new(label),
               organization_id: c.org.organization_id,
               mission_id: c.mission.mission_id,
               isolation_level: :mission_isolated,
               adapter: Cadence.Dashboards.Sources.Telemetry
             })

    source
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

  defp native(value) do
    {output, status} =
      System.cmd("node", [@renderer, Jason.encode!(value)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, json] = Regex.run(~r/CADENCE_SOURCES_CALLS=([^\n]+)/, output)
    Jason.decode!(json)
  end

  defp browser_fixture(name, value) do
    if directory = System.get_env("CADENCE_SOURCES_SNAPSHOT_DIR") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, name <> ".json"), Jason.encode!(value))
    end
  end
end
