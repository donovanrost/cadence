defmodule CadenceWeb.SpacecraftTelemetryDecomLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias CadenceWeb.TestFixtures

  defp setup_session do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary")
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")
    {TestFixtures.member_conn(user), org, mission, spacecraft}
  end

  defp persist_revision!(org, mission) do
    {:ok, database} =
      Catalog.create_database(org.organization_id, mission.mission_id, %{
        name: "Bus",
        slug: "bus",
        catalog_family: :combined,
        default_importer_key: "cadence_yaml"
      })

    yaml = """
    packets:
      - name: HEALTH
        apid: 42
        items:
          - name: mode
            data_type: uint
            bit_offset: 0
            bit_size: 8
    commands: []
    """

    artifact =
      Artifact.new(%{
        mission_id: mission.mission_id,
        catalog_database_id: database.catalog_database_id,
        catalog_family: :combined,
        artifact_name: "bus.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: yaml
      })

    {:ok, run} =
      Catalog.start_revision_import(
        org.organization_id,
        mission.mission_id,
        database.catalog_database_id,
        artifact,
        "cadence_yaml",
        metadata: %{"revision_label" => "Rev 1"}
      )

    {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(
        org.organization_id,
        mission.mission_id,
        completed.import_run_id
      )

    revision
  end

  test "renders status card and links back to spacecraft" do
    {conn, _org, mission, spacecraft} = setup_session()

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    assert html =~ "Telemetry Decom"
    assert html =~ "Not configured"
    assert html =~ spacecraft.display_name
  end

  test "toggling an APID autosaves and updates the preview count" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    html =
      view
      |> element("input[phx-click='toggle_apid'][phx-value-apid='42']")
      |> render_click()

    assert html =~ "Matched packets"

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == [42]
  end

  @tag :skip
  test "disabled configs can still be applied from the same screen" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    _html =
      view
      |> form("#telemetry-decom-config-form", %{
        "config" => %{
          "catalog_revision_id" => revision.catalog_revision_id,
          "handled_apids" => "42"
        }
      })
      |> render_submit()

    _html =
      view
      |> element("#telemetry-decom-enable-button")
      |> render_click()

    html =
      view
      |> element("#telemetry-decom-disable-button")
      |> render_click()

    assert html =~ "Apply Mission Changes"
    assert html =~ "Applied configuration is out of date"

    html =
      view
      |> element("#telemetry-decom-enable-button")
      |> render_click()

    assert html =~ "Disabled"

    assert {:ok, disabled} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    refute disabled.enabled
  end

  test "focuses the page on catalog revision and handled APID selection" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    assert html =~ "Catalog revision"
    assert html =~ "Handled APIDs"
    refute html =~ "Data Source"
    refute html =~ "New Data Source"
    refute html =~ "Ingress source ref"
  end

  @tag :skip
  test "shows a validation error for APIDs not found in the selected revision" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    html =
      view
      |> form("#telemetry-decom-config-form", %{
        "config" => %{
          "catalog_revision_id" => revision.catalog_revision_id,
          "handled_apids" => "999"
        }
      })
      |> render_submit()

    assert html =~ "APIDs not found in this revision"
  end

  test "spacecraft show page surfaces the telemetry decom section" do
    {conn, _org, mission, spacecraft} = setup_session()

    {:ok, _view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

    assert html =~ "Telemetry Decom"
    assert html =~ "Not configured"
    assert html =~ "Configure"
  end
end
