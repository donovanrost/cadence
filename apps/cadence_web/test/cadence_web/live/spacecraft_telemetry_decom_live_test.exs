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
    PacketBindings,
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

  test "Manage saves catalog context and directs packet selection to the shared surface" do
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

    view
    |> element("#telemetry-decom-save-revision")
    |> render_click()

    assert has_element?(
             view,
             "#application-activation-preflight[data-preflight-state='blocked'][data-activation-ready='false']"
           )

    assert has_element?(view, "#application-preflight-check-packet-apid-binding")
    assert has_element?(view, "#telemetry-decom-open-packet-bindings")
    refute has_element?(view, "input[phx-click='toggle_apid']")

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == []
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

  test "renders and saves shared packet-model inputs through the declarative host" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    {:ok, snapshot} =
      Catalog.fetch_telemetry_snapshot(
        org.organization_id,
        mission.mission_id,
        revision.telemetry_snapshot_id
      )

    packet = List.first(snapshot.packets)

    manage_path =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"

    {:ok, manage, _html} = live(conn, manage_path)

    manage
    |> element("#telemetry-decom-save-revision")
    |> render_click()

    packet_bindings_path =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings"

    {:ok, view, _html} = live(conn, packet_bindings_path)

    assert has_element?(
             view,
             "#spacecraft-application-host[data-application-key='telemetry_decom'][data-surface-id='packet_bindings'][data-renderer='declarative']"
           )

    assert has_element?(view, "#application-surface-navigation")
    assert has_element?(view, "#packet-bindings-surface[data-activation-state='configured']")
    assert has_element?(view, "#packet-bindings-form")

    assert has_element?(
             view,
             "#packet-binding-groups details[data-apid='42'][data-state='available']"
           )

    refute has_element?(
             view,
             "#packet-binding-groups input[name='application_action[selected_packet_ids][]'][checked]"
           )

    assert has_element?(
             view,
             "#packet-binding-groups tr[data-resource-kind='field'][data-compatibility='compatible']",
             "mode"
           )

    view
    |> form("#packet-bindings-form", %{
      "application_action" => %{"selected_packet_ids" => [packet.packet_id]}
    })
    |> render_submit()

    assert has_element?(
             view,
             "#application-action-feedback[data-kind='success'][data-code='action_completed']",
             "Packet bindings saved"
           )

    scope = installation_read_scope(org.organization_id)
    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    assert {:ok, installation} =
             ApplicationInstallations.fetch(scope, host_context, "telemetry_decom")

    assert {:ok, [configuration]} =
             PacketBindings.list(
               scope,
               host_context,
               installation.application_installation_id
             )

    assert configuration.configuration_version == 1
    assert Enum.map(configuration.bindings, & &1.apid) == [42]
    assert has_element?(view, "#packet-bindings-surface[data-activation-state='configured']")
    assert has_element?(view, "#packet-binding-groups details[data-state='selected']")
  end

  test "renders compiler findings through the host diagnostic contract" do
    {conn, org, mission, spacecraft} = setup_session()

    revision =
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

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

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
    revision = persist_revision!(org, mission)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

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
    revision = persist_revision!(org, mission)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

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

  test "focuses the page on catalog revision and packet input selection" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    {:ok, view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    assert html =~ "Catalog revision"
    assert html =~ "Packet inputs"
    assert html =~ "Open Packet Bindings"

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

  test "Manage exposes no legacy packet-selection mutation controls" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    refute has_element?(view, "#telemetry-decom-select-all")
    refute has_element?(view, "#telemetry-decom-clear")
    refute has_element?(view, "#telemetry-decom-apid-table")
    assert has_element?(view, "#telemetry-decom-open-packet-bindings")
  end

  test "saving catalog context without packet bindings remains blocked for activation" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    view
    |> element("#telemetry-decom-save-revision")
    |> render_click()

    assert has_element?(
             view,
             "#application-preflight-check-packet-apid-binding[data-check-state='blocked']"
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

  test "shows a shared APID reader without preventing activation" do
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
             "#application-preflight-check-packet-apid-binding[data-check-state='ready']"
           )

    assert has_element?(view, "#telemetry-decom-enable-button:not([disabled])")
    html = render(view)
    refute html =~ "conflict"
    assert html =~ "other applications may read the same packets"
  end

  test "Packet Bindings groups packet identity and compatible resources" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings"
      )

    assert has_element?(view, "#packet-binding-groups details[data-apid='42']", "HEALTH")
    assert has_element?(view, "#packet-binding-groups tr[data-resource-kind='field']", "mode")
  end

  test "selected Packet Bindings expand their resource ledger by default" do
    {conn, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings"
      )

    assert has_element?(view, "#packet-binding-groups details[data-state='selected'][open]")
    assert has_element?(view, "#packet-binding-groups", "mode")
  end

  test "switching catalog revision clears the legacy APID selection without a second mutation UI" do
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

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: rev_a.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    view
    |> form("#telemetry-decom-revision-form", %{
      "catalog_revision_id" => rev_b.catalog_revision_id
    })
    |> render_change()

    refute has_element?(view, "#telemetry-decom-dropped-unknowns")
    refute has_element?(view, "#telemetry-decom-drop-unknowns")
    assert has_element?(view, "#telemetry-decom-open-packet-bindings")

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.catalog_revision_id == rev_b.catalog_revision_id
    assert config.handled_apids == []
  end
end
