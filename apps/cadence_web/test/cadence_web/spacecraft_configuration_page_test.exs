defmodule CadenceWeb.SpacecraftConfigurationPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.MissionModels
  alias CadenceWeb.TestFixtures

  @contract Path.expand(
              "../../../../frontend/apps/host/src/mission-and-spacecraft/features/spacecraft-configuration/contracts.ts",
              __DIR__
            )

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission)

    %{
      conn: TestFixtures.member_conn(user),
      mission: mission,
      craft: craft,
      path: "/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}"
    }
  end

  test "the real producer serves a profile-optional workspace accepted by its Vue decoder", c do
    {:ok, view, _} = live(c.conn, c.path)
    page = page(view)
    assert page["page"] == "spacecraft_configuration"
    assert page["status"] == "ready"
    assert page["data"]["document"]["protocol"] == nil

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        [
          "--no-warnings",
          "--input-type=module",
          "-e",
          "import {readConfiguration} from #{Jason.encode!(@contract)}; readConfiguration(JSON.parse(process.argv[1]));",
          Jason.encode!(page["data"])
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert has_element?(view, "#application-shell")
  end

  test "saving through the active route persists a draft, rejects stale evidence and never activates it",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    data = page(view)["data"]

    render_hook(view, "host:spacecraft-configuration", %{
      "path" => c.path,
      "event" => "save",
      "input" => %{"token" => data["token"], "document" => data["document"]}
    })

    assert page(view)["data"]["saved_version"] == 1

    assert ConfigurationDrafts.latest(
             c.mission.organization_id,
             c.mission.mission_id,
             c.craft.spacecraft_id
           ).version == 1

    render_hook(view, "host:spacecraft-configuration", %{
      "path" => c.path,
      "event" => "save",
      "input" => %{"token" => data["token"], "document" => data["document"]}
    })

    assert page(view)["data"]["saved_version"] == 1

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(
               c.mission.organization_id,
               c.mission.mission_id
             )

    token = page(view)["data"]["token"]
    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission.mission_id}/catalog"})

    render_hook(view, "host:spacecraft-configuration", %{
      "path" => c.path,
      "event" => "save",
      "input" => %{"token" => token, "document" => data["document"]}
    })

    assert ConfigurationDrafts.latest(
             c.mission.organization_id,
             c.mission.mission_id,
             c.craft.spacecraft_id
           ).version == 1
  end

  test "matching invalidations refresh the workspace and detached routes do not react", c do
    {:ok, view, _} = live(c.conn, c.path <> "?section=changes")
    assert page(view)["data"]["section"] == "changes"

    send(
      view.pid,
      {:spacecraft_configuration_changed, c.mission.organization_id, c.mission.mission_id}
    )

    assert has_element?(view, "#application-shell")
    assert page(view)["data"]["section"] == "changes"
    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission.mission_id}/catalog"})

    send(
      view.pid,
      {:spacecraft_configuration_changed, c.mission.organization_id, c.mission.mission_id}
    )

    assert has_element?(view, "#application-shell")
    assert page(view) == nil
  end

  test "saving a catalog with persisted legalization warnings keeps the channel alive", c do
    revision =
      CatalogFixtures.persist_imported_revision!(c.mission.organization_id, c.mission.mission_id,
        yaml: """
        packets:
          - name: HEALTH
            apid: 42
            items:
              - name: temperature
                data_type: uint
                bit_offset: 0
                bit_size: 8
                conversion:
                  type: polynomial
                  coefficients: [0, 1]
        commands: []
        """
      )

    assert {:ok, plan} =
             MissionModels.fetch_plan(
               c.mission.organization_id,
               c.mission.mission_id,
               revision.mission_model_revision_id,
               :telemetry
             )

    assert Enum.any?(plan.diagnostics, fn diagnostic ->
             diagnostic.stage == :legalization and diagnostic.severity == :warning
           end)

    {:ok, view, _} = live(c.conn, c.path)
    data = page(view)["data"]

    document =
      Map.merge(data["document"], %{
        "catalog_revision_id" => revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "handled_apids" => [42]
      })

    render_hook(view, "host:spacecraft-configuration", %{
      "path" => c.path,
      "event" => "save",
      "input" => %{"token" => data["token"], "document" => document}
    })

    assert Process.alive?(view.pid)
    assert has_element?(view, "#application-shell")
    assert page(view)["data"]["saved_version"] == 1
    assert page(view)["data"]["document"]["catalog_revision_id"] == revision.catalog_revision_id

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(
               c.mission.organization_id,
               c.mission.mission_id
             )
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["spacecraft_page"]
end
