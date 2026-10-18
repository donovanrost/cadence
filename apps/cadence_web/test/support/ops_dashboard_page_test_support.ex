defmodule CadenceWeb.OpsDashboardPageTestSupport do
  @moduledoc false
  # Shared setup and host-protocol helpers for the Ops dashboard page tests.

  import ExUnit.Assertions
  import Phoenix.LiveViewTest
  alias Cadence.Dashboards.{CurrentVersions, DocumentCodec, Documents}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/dashboard/producer-render-check.mjs",
              __DIR__
            )

  def dashboard_page_setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "dashboard-" <> Ecto.UUID.generate(),
        metadata: %{secret: "private-authoring-metadata"}
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    path = "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}"

    %{
      org: org,
      mission: mission,
      user: user,
      document: document,
      conn: TestFixtures.member_conn(user),
      path: path,
      edit: path <> "/edit"
    }
  end

  def assert_renders(pages) do
    node = System.find_executable("node") || flunk("Node is required for the page contract")

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!(pages)], stderr_to_stdout: true)

    assert status == 0, output
  end

  def save(c, document, version) do
    assert {:ok, _} =
             CurrentVersions.save(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               document,
               expected_version: version,
               created_by: c.user.user_id
             )
  end

  def query(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => "dashboards.workspace",
      "token" => page["token"],
      "event" => event,
      "input" => input
    })
  end

  def page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  def refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  def control(page),
    do: %{
      "expected_version" => page["data"]["edit"]["document_version"],
      "expected_revision" => page["data"]["edit"]["revision"]
    }

  def stage(view, path, page, event, sequence, command),
    do: action(view, path, page, event, sequence, Map.merge(command, control(page)))

  def action(view, path, page, event, sequence, command),
    do: render_hook(view, "host:ops-page", request(path, page, event, sequence, command))

  def request(path, page, event, sequence, command) do
    %{
      "path" => path,
      "id" => "dashboards.workspace",
      "token" => page["token"],
      "event" => event,
      "input" => %{"sequence" => sequence, "command" => command}
    }
  end

  def search(path, page, fields, query) do
    %{
      "path" => path,
      "id" => "dashboards.workspace",
      "token" => page["token"],
      "event" => "search_observables",
      "input" => %{
        "query" => query,
        "fields" => fields,
        "expected_version" => get_in(page, ["data", "edit", "document_version"]) || 1,
        "expected_revision" => get_in(page, ["data", "edit", "revision"]) || 0
      }
    }
  end

  def fetch(c) do
    {:ok, document} =
      Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    document
  end

  def versions(c),
    do:
      Documents.list_versions(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )
end
