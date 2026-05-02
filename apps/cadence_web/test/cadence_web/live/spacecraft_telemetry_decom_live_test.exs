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

  defp persist_revision!(org, mission, opts \\ []) do
    revision_label = Keyword.get(opts, :revision_label, "Rev 1")
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, database} =
      Catalog.create_database(org.organization_id, mission.mission_id, %{
        name: "Bus " <> suffix,
        slug: "bus-" <> suffix,
        catalog_family: :combined,
        default_importer_key: "cadence_yaml"
      })

    yaml =
      Keyword.get(
        opts,
        :yaml,
        """
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
      )

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
        metadata: %{"revision_label" => revision_label}
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
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry"
      )

    assert html =~ "Telemetry Interpretation"
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

  test "disable button rolls back the enabled flag" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    view |> element("input[phx-click='toggle_apid'][phx-value-apid='42']") |> render_click()

    html =
      view
      |> element("#telemetry-decom-disable-button")
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

  test "spacecraft show page surfaces the telemetry decom section" do
    {conn, _org, mission, spacecraft} = setup_session()

    {:ok, _view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

    assert html =~ "Telemetry Interpretation"
    assert html =~ "Not configured"
    assert html =~ "Configure"

    assert html =~
             ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry"
  end

  test "select-all-unclaimed picks every non-conflicting APID and autosaves" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    _html =
      view
      |> element("#telemetry-decom-select-all")
      |> render_click()

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == [42]
  end

  test "clear empties the selection and resets handled APIDs in the saved config" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    view
    |> element("#telemetry-decom-select-all")
    |> render_click()

    html =
      view
      |> element("#telemetry-decom-clear")
      |> render_click()

    assert html =~ "Handled APIDs · 0 / 1"

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == []
  end

  test "filter narrows visible rows to matches on APID or name" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    html =
      view
      |> form("#telemetry-decom-filter-form", %{"filter" => "health"})
      |> render_change()

    assert html =~ "HEALTH"
  end

  test "clicking a row expands it and shows the packet entries" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    html =
      view
      |> element("#apid-row-42-toggle")
      |> render_click()

    assert html =~ ~s(id="apid-row-42-detail")
    assert html =~ "mode"
  end

  test "switching to a revision without some selected APIDs shows the drop-unknowns banner" do
    {conn, org, mission, spacecraft} = setup_session()

    rev_a = persist_revision!(org, mission)

    rev_b =
      persist_revision!(org, mission,
        revision_label: "Rev 2",
        yaml: """
        packets:
          - name: OTHER
            apid: 7
            items:
              - name: v
                data_type: uint
                bit_offset: 0
                bit_size: 8
        commands: []
        """
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    # The page defaults to the highest-numbered revision (rev_b). Switch to rev_a first.
    view
    |> form("#telemetry-decom-revision-form", %{
      "catalog_revision_id" => rev_a.catalog_revision_id
    })
    |> render_change()

    # select APID 42 in rev A
    view |> element("input[phx-click='toggle_apid'][phx-value-apid='42']") |> render_click()

    # switch to rev B (which only has APID 7)
    html =
      view
      |> form("#telemetry-decom-revision-form", %{
        "catalog_revision_id" => rev_b.catalog_revision_id
      })
      |> render_change()

    assert html =~ "previously selected"
    assert html =~ "42"

    # click "Drop them"
    html =
      view
      |> element("#telemetry-decom-drop-unknowns")
      |> render_click()

    refute html =~ "previously selected"
  end
end
