defmodule CadenceWeb.SpacecraftTelemetryDecomLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{
    ApplicationBinding,
    ApplicationBindingStore,
    ApplicationInstallations,
    HostContext,
    TelemetryDecom
  }

  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias CadenceWeb.TestFixtures

  defp setup_session do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary")
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization: org,
        organization_membership: membership
      })

    {:ok, _installation} =
      ApplicationInstallations.install(
        scope,
        HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
        "telemetry_decom"
      )

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

    {:ok, view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    assert html =~ "Telemetry Decom"
    assert html =~ "Not configured"
    assert html =~ spacecraft.display_name
    assert has_element?(view, "#application-activation-preflight[data-preflight-state='blocked']")

    assert has_element?(
             view,
             "#application-activation-preflight[data-activation-ready='false']"
           )
  end

  test "toggling an APID autosaves and updates the preview count" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    assert has_element?(
             view,
             "#spacecraft-application-host[data-application-key='telemetry_decom'][data-application-version='1'][data-surface-id='manage']"
           )

    html =
      view
      |> element("input[phx-click='toggle_apid'][phx-value-apid='42']")
      |> render_click()

    assert html =~ "Matched packets"

    assert has_element?(
             view,
             "#application-activation-preflight[data-preflight-state='ready'][data-activation-ready='true']"
           )

    assert has_element?(view, "#application-preflight-check-packet-apid-claim")

    assert has_element?(
             view,
             "#telemetry-decom-enable-button:not([disabled])[data-application-lifecycle-action='request_activation'][data-lifecycle-execution='approval_required'][data-confirmation-required='true'][data-confirmation-title='Request mission changes?']"
           )

    assert has_element?(
             view,
             "#telemetry-decom-enable-button[data-confirm*='will not become live']"
           )

    assert has_element?(
             view,
             "#telemetry-decom-disable-button[data-application-lifecycle-action='disable'][data-lifecycle-execution='immediate'][data-confirmation-required='true'][data-confirmation-tone='attention']"
           )

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == [42]
    assert config.configuration_version == 1

    assert {:ok, installation} =
             ApplicationInstallations.fetch(
               installation_read_scope(org.organization_id),
               HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
               "telemetry_decom"
             )

    assert installation.configuration_ref.version == 1

    assert installation.configuration_ref.id ==
             "application_binding:#{spacecraft.spacecraft_id}:telemetry_decom"
  end

  test "renders compiler findings through the host diagnostic contract" do
    {conn, org, mission, spacecraft} = setup_session()

    _revision =
      persist_revision!(org, mission,
        yaml: """
        packets:
          - name: HEALTH
            apid: 42
            items:
              - name: mode
                data_type: string
                bit_offset: 0
                bit_size: 32
        commands: []
        """
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    view
    |> element("input[phx-click='toggle_apid'][phx-value-apid='42']")
    |> render_click()

    assert has_element?(
             view,
             "#telemetry-decom-diagnostics[data-diagnostic-severity='error'][data-diagnostic-count='1'][data-diagnostic-total='1']"
           )

    assert has_element?(
             view,
             "#telemetry-decom-diagnostics-item-compiler-001[data-diagnostic-code='telemetry_compiler.type_unsupported'][data-diagnostic-severity='error']",
             "Type unsupported"
           )
  end

  test "disable button rolls back the enabled flag" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
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

    assert {:ok, installation} =
             ApplicationInstallations.fetch(
               installation_read_scope(org.organization_id),
               HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
               "telemetry_decom"
             )

    assert installation.lifecycle_state == :disabled
  end

  test "requesting mission changes creates a pending governed activation" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    view
    |> element("input[phx-click='toggle_apid'][phx-value-apid='42']")
    |> render_click()

    html =
      view
      |> element("#telemetry-decom-enable-button")
      |> render_click()

    assert html =~ "Telemetry Decom activation requested"
    assert has_element?(view, "#telemetry-decom-activation-pending")

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(
               org.organization_id,
               mission.mission_id
             )

    {:ok, remounted_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    assert has_element?(remounted_view, "#telemetry-decom-activation-pending")
  end

  defp installation_read_scope(organization_id) do
    %Scope{
      actor_kind: :user,
      organization_id: organization_id,
      user: %{},
      capabilities: MapSet.new([:platform_admin])
    }
  end

  test "focuses the page on catalog revision and handled APID selection" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    {:ok, view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    assert html =~ "Catalog revision"
    assert html =~ "Packet Claims"

    assert has_element?(
             view,
             "#telemetry-decom-revision-select option[value='#{revision.catalog_revision_id}']",
             "Rev 1 (#1)"
           )

    refute html =~ "Data Source"
    refute html =~ "New Data Source"
    refute html =~ "Ingress source ref"
  end

  test "spacecraft show page surfaces the telemetry decom section" do
    {conn, _org, mission, spacecraft} = setup_session()

    {:ok, view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

    assert html =~ "Applications"
    assert has_element?(view, "#spacecraft-overview-applications", "Not configured")
    assert has_element?(view, "#spacecraft-overview-applications a", "Review applications")

    assert html =~
             ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
  end

  test "select-all-unclaimed picks every non-conflicting APID and autosaves" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
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
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    view
    |> element("#telemetry-decom-select-all")
    |> render_click()

    html =
      view
      |> element("#telemetry-decom-clear")
      |> render_click()

    assert html =~ "Packet Claims · 0 / 1"

    assert has_element?(
             view,
             "#application-preflight-check-packet-apid-claim[data-check-state='blocked']"
           )

    assert has_element?(view, "#telemetry-decom-enable-button[disabled]")

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == []
  end

  test "shows a blocking resource conflict and prevents activation" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    assert {:ok, config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    assert {:ok, _binding} =
             ApplicationBindingStore.upsert(
               ApplicationBinding.new(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 spacecraft_id: spacecraft.spacecraft_id,
                 application_key: :event_reporting,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: config.source_endpoint_id
               })
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    assert has_element?(
             view,
             "#application-preflight-check-packet-apid-claim[data-check-state='blocked']"
           )

    assert has_element?(view, "#telemetry-decom-enable-button[disabled]")
  end

  test "filter narrows visible rows to matches on APID or name" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
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
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
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
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
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
