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

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, State, Update}
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

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

    {:ok, _approved_model} =
      Cadence.MissionModels.approve_revision(
        org.organization_id,
        mission.mission_id,
        revision.mission_model_revision_id,
        %{"kind" => "test_fixture", "id" => "telemetry-decom-live"}
      )

    {:ok, plans} =
      Cadence.MissionModels.fetch_runtime_plans(
        org.organization_id,
        mission.mission_id,
        revision.mission_model_revision_id
      )

    {:ok, [packet | _rest]} = MissionModelPlanDecoder.telemetry_packet_definitions(plans)
    [field | _rest] = packet.fields

    update =
      Update.new(%{
        update_id: "telemetry-decom-live-qualification",
        parameter_id: field.parameter_id,
        qualified_name: field.qualified_name,
        value: 1,
        raw_value: 1,
        quality: :good,
        generation_time: ~U[2026-08-12 12:00:00Z],
        receipt_time: ~U[2026-08-12 12:00:00Z],
        producer_kind: :container,
        producer_id: packet.packet_definition_id,
        metadata: %{mission_id: mission.mission_id}
      })

    {:ok, result, %State{}} =
      SemanticRuntime.process(%State{}, [update], PlanDecoder.decode(plans))

    expected_result_sha256 =
      ContentHash.term_sha256(%{
        updates:
          Enum.map(result.parameter_updates, fn parameter_update ->
            {parameter_update.parameter_id, parameter_update.value, parameter_update.quality,
             parameter_update.generation_time, parameter_update.receipt_time}
          end),
        monitoring:
          Enum.map(result.monitoring_results, fn monitoring ->
            {monitoring.policy_id, monitoring.parameter_id, monitoring.effective_state,
             monitoring.transition}
          end)
      })

    qualification_user =
      User.new(%{
        user_id: "telemetry-decom-live-qualification",
        email: "telemetry-decom-live-qualification@example.test",
        display_name: "Telemetry Decom Live Qualification",
        capabilities: [:platform_admin]
      })

    qualification_scope =
      Scope.new(%{
        user: qualification_user,
        organization_id: org.organization_id,
        admin_mode?: true
      })

    {:ok, _qualification_case} =
      Cadence.MissionModels.register_qualification_case(
        qualification_scope,
        mission.mission_id,
        "Telemetry Decom Live nominal packet",
        [update],
        expected_result_sha256: expected_result_sha256
      )

    revision
  end

  test "renders status card and links back to spacecraft" do
    {conn, _org, mission, spacecraft} = setup_session()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    assert has_element?(view, "#spacecraft-telemetry-decom-component.contents")

    vue = telemetry_decom_vue(view)

    assert vue.component == "SpacecraftTelemetryDecom"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.slots == %{}

    assert vue.handlers == %{
             "change_revision" => JS.push("change_revision"),
             "disable" => JS.push("disable"),
             "enable" => JS.push("enable"),
             "save_catalog_revision" => JS.push("save_catalog_revision")
           }

    assert vue.props["page"] == page_props(mission, spacecraft)
    assert vue.props["card"] == %{"id" => "telemetry-decom-card"}
    assert vue.props["status"] == status_props("not_configured")
    assert vue.props["revision"] == nil

    assert vue.props["no_revisions"] == %{
             "message" =>
               "No packet catalog revisions are available for this mission yet. Import a catalog revision first.",
             "action" => %{
               "label" => "Go to catalog",
               "href" => "/missions/#{mission.mission_id}/catalog"
             }
           }

    assert vue.props["packet_handoff"] == nil
    assert vue.props["preview"] == nil
    assert vue.props["pending_activation"] == nil

    assert vue.props["lifecycle_actions"] == %{
             "empty_message" => "Select at least one APID to save and apply.",
             "disable" => nil,
             "enable" => nil
           }

    preflight = vue.props["preflight"]
    assert preflight == blocked_preflight_props()

    assert Enum.map(preflight["checks"], & &1["id"]) == [
             "application-preflight-check-configuration",
             "application-preflight-check-packet-apid-binding",
             "application-preflight-check-runtime-compilation"
           ]

    assert_json_safe(vue)
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

    render_hook(view, "save_catalog_revision", %{})

    vue = telemetry_decom_vue(view)

    assert vue.props["preflight"]["state"] == "blocked"
    assert vue.props["preflight"]["activation_ready"] == false

    assert preflight_check(vue, "packet-apid-binding")["id"] ==
             "application-preflight-check-packet-apid-binding"

    assert vue.props["packet_handoff"]["action"]["id"] ==
             "telemetry-decom-open-packet-bindings"

    refute Map.has_key?(vue.props["packet_handoff"], "toggle_apid")

    assert vue.props["lifecycle_actions"] == %{
             "empty_message" => nil,
             "disable" => disable_action_props(),
             "enable" => enable_action_props(true)
           }

    assert Map.drop(vue.props["status"], ["saved_label"]) == %{
             "state" => "configured",
             "tone" => "info",
             "label" => "Configured — not yet applied",
             "description" => "Choices are saved. Request mission changes to publish them."
           }

    assert String.starts_with?(vue.props["status"]["saved_label"], "Saved ")

    assert vue.props["preview"]["stats"] == [
             %{
               "id" => "telemetry-decom-preview-matched-packets",
               "label" => "Matched packets",
               "value" => 0
             },
             %{
               "id" => "telemetry-decom-preview-compiled-defs",
               "label" => "Compiled defs",
               "value" => 0
             },
             %{
               "id" => "telemetry-decom-preview-unassigned-apids",
               "label" => "Unassigned APIDs",
               "value" => 1
             },
             %{
               "id" => "telemetry-decom-preview-notices",
               "label" => "Notices",
               "value" => 0
             }
           ]

    assert vue.props["preview"]["diagnostics"] == nil
    assert_json_safe(vue)

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

    {:ok, telemetry} =
      TelemetryProjection.load(org.organization_id, mission.mission_id, revision)

    packet = List.first(telemetry.packet_definitions)

    manage_path =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"

    {:ok, manage, _html} = live(conn, manage_path)

    render_hook(manage, "save_catalog_revision", %{})

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
      "application_action" => %{"selected_packet_ids" => [packet.packet_definition_id]}
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
                data_type: uint
                bit_offset: 0
                bit_size: 8
                conversion:
                  type: polynomial
                  coefficients: [0.0, 1.0]
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

    diagnostics = telemetry_decom_vue(view).props["preview"]["diagnostics"]

    assert diagnostics["id"] == "telemetry-decom-diagnostics"
    assert diagnostics["severity"] == "warning"
    assert diagnostics["count"] == 1
    assert diagnostics["total_count"] == 1

    assert [diagnostic] = diagnostics["items"]

    assert Map.take(diagnostic, [
             "id",
             "diagnostic_id",
             "code",
             "severity",
             "title",
             "detail"
           ]) == %{
             "id" => "telemetry-decom-diagnostics-item-compiler-001",
             "diagnostic_id" => "compiler-001",
             "code" => "MM_CALIBRATOR_RUNTIME_UNSUPPORTED",
             "severity" => "warning",
             "title" => "Mm calibrator runtime unsupported",
             "detail" => "calibrator is preserved but is not executable by telemetry target v1"
           }

    assert is_binary(diagnostic["value"])

    assert_json_safe(telemetry_decom_vue(view))
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

    render_hook(view, "disable", %{"action-id" => "disable"})

    disabled_vue = telemetry_decom_vue(view)
    assert disabled_vue.props["status"]["label"] == "Disabled"
    assert disabled_vue.props["lifecycle_actions"]["disable"] == nil
    assert disabled_vue.props["lifecycle_actions"]["enable"] == enable_action_props(false)
    assert disabled_vue.props["preflight"]["state"] == "attention"
    assert disabled_vue.props["preflight"]["activation_ready"]

    assert has_element?(
             view,
             "#flash-info",
             "Telemetry Decom disabled for this spacecraft. Apply mission changes to remove it from the live mission."
           )

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

    render_hook(view, "enable", %{"action-id" => "request_activation"})

    assert has_element?(view, "#flash-info", "Telemetry Decom activation requested")

    activation_vue = telemetry_decom_vue(view)
    pending = activation_vue.props["pending_activation"]
    assert pending["id"] == "telemetry-decom-activation-pending"
    assert is_binary(pending["activation_request_id"])

    assert pending["message_before"] == "Activation request"

    assert pending["message_after"] ==
             "is waiting for approval from a different mission administrator."

    assert activation_vue.props["lifecycle_actions"]["enable"] == enable_action_props(true)

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

    assert telemetry_decom_vue(remounted_view).props["pending_activation"]["id"] ==
             "telemetry-decom-activation-pending"
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

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    props = telemetry_decom_vue(view).props

    assert props["revision"]["field"]["label"] == "Catalog revision"
    assert props["packet_handoff"]["label"] == "Packet inputs"
    assert props["packet_handoff"]["action"]["label"] == "Open Packet Bindings"

    assert props["revision"]["field"]["options"] == [
             %{"label" => "Rev 1 (#1)", "value" => revision.catalog_revision_id}
           ]

    serialized_props = inspect(props)
    refute serialized_props =~ "Data Source"
    refute serialized_props =~ "New Data Source"
    refute serialized_props =~ "Ingress source ref"
  end

  test "spacecraft show page surfaces the telemetry decom section" do
    {conn, _org, mission, spacecraft} = setup_session()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

    vue = LiveVue.Test.get_vue(view, id: "spacecraft-show-component")
    assert vue.component == "SpacecraftShow"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    applications = vue.props["applications"]
    assert applications["title"] == "Applications"

    assert [telemetry_decom] =
             Enum.filter(
               applications["rows"],
               &(&1["application_key"] == "telemetry_decom")
             )

    assert telemetry_decom["status"] == %{"label" => "Not configured", "tone" => "blocked"}

    application_workflow =
      Enum.find(vue.props["workflow_cards"], &(&1["id"] == "spacecraft-overview-applications"))

    applications_href =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

    assert application_workflow["value"] == "Not configured"

    assert application_workflow["action"] == %{
             "label" => "Review applications",
             "href" => applications_href
           }
  end

  test "Manage exposes no legacy packet-selection mutation controls" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    props = telemetry_decom_vue(view).props
    ids = dto_ids(props)
    refute "telemetry-decom-select-all" in ids
    refute "telemetry-decom-clear" in ids
    refute "telemetry-decom-apid-table" in ids

    assert props["packet_handoff"]["action"]["id"] ==
             "telemetry-decom-open-packet-bindings"
  end

  test "saving catalog context without packet bindings remains blocked for activation" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
      )

    render_hook(view, "save_catalog_revision", %{})

    vue = telemetry_decom_vue(view)

    assert preflight_check(vue, "packet-apid-binding")["state"] == "blocked"

    assert vue.props["lifecycle_actions"]["enable"]["disabled"]

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

    vue = telemetry_decom_vue(view)

    assert preflight_check(vue, "packet-apid-binding")["state"] == "ready"

    refute vue.props["lifecycle_actions"]["enable"]["disabled"]
    refute inspect(vue.props) =~ "conflict"

    assert vue.props["packet_handoff"]["detail"] ==
             "APIDs route traffic; other applications may read the same packets and fields."
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

    render_hook(view, "change_revision", %{
      "catalog_revision_id" => rev_b.catalog_revision_id
    })

    props = telemetry_decom_vue(view).props
    ids = dto_ids(props)

    refute "telemetry-decom-dropped-unknowns" in ids
    refute "telemetry-decom-drop-unknowns" in ids

    assert props["packet_handoff"]["action"]["id"] ==
             "telemetry-decom-open-packet-bindings"

    assert props["revision"]["field"]["value"] == rev_b.catalog_revision_id

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.catalog_revision_id == rev_b.catalog_revision_id
    assert config.handled_apids == []
  end

  defp telemetry_decom_vue(view) do
    LiveVue.Test.get_vue(view, id: "spacecraft-telemetry-decom-component")
  end

  defp preflight_check(vue, check_id) do
    Enum.find(vue.props["preflight"]["checks"], &(&1["check_id"] == check_id))
  end

  defp dto_ids(value) when is_list(value), do: Enum.flat_map(value, &dto_ids/1)

  defp dto_ids(value) when is_map(value) do
    own_id = if is_binary(value["id"]), do: [value["id"]], else: []
    own_id ++ Enum.flat_map(Map.values(value), &dto_ids/1)
  end

  defp dto_ids(_value), do: []

  defp page_props(mission, spacecraft) do
    %{
      "id" => "spacecraft-telemetry-decom-page",
      "title" => "Telemetry Decom",
      "subtitle" =>
        "Application packet inputs and publication state for #{spacecraft.display_name}.",
      "breadcrumbs" => [
        %{
          "id" => "telemetry-decom-mission-breadcrumb",
          "label" => mission.display_name,
          "href" => "/missions/#{mission.mission_id}"
        },
        %{
          "id" => "telemetry-decom-spacecraft-list-breadcrumb",
          "label" => "Spacecraft",
          "href" => "/missions/#{mission.mission_id}/spacecraft"
        },
        %{
          "id" => "telemetry-decom-spacecraft-breadcrumb",
          "label" => spacecraft.display_name,
          "href" =>
            "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
        },
        %{
          "id" => "telemetry-decom-applications-breadcrumb",
          "label" => "Applications",
          "href" =>
            "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
        },
        %{
          "id" => "telemetry-decom-current-breadcrumb",
          "label" => "Telemetry Decom",
          "href" => nil
        }
      ]
    }
  end

  defp status_props("not_configured") do
    %{
      "state" => "not_configured",
      "tone" => "blocked",
      "label" => "Not configured",
      "description" =>
        "Choose a catalog revision and packet inputs, then apply mission changes.",
      "saved_label" => nil
    }
  end

  defp blocked_preflight_props do
    %{
      "id" => "application-activation-preflight",
      "checks_id" => "application-preflight-checks",
      "state" => "blocked",
      "activation_ready" => false,
      "check_count" => 3,
      "application_version" => 1,
      "summary" => "3 blocking checks must be resolved before activation.",
      "label" => "Blocked",
      "checks" => [
        %{
          "id" => "application-preflight-check-configuration",
          "check_id" => "configuration",
          "category" => "configuration",
          "state" => "blocked",
          "title" => "Configuration required",
          "detail" =>
            "Select a catalog revision and packet APIDs before requesting mission changes.",
          "value" => nil
        },
        %{
          "id" => "application-preflight-check-packet-apid-binding",
          "check_id" => "packet-apid-binding",
          "category" => "resource",
          "state" => "blocked",
          "title" => "Packet binding unavailable",
          "detail" => "No APIDs are declared because the application is not configured.",
          "value" => nil
        },
        %{
          "id" => "application-preflight-check-runtime-compilation",
          "check_id" => "runtime-compilation",
          "category" => "compilation",
          "state" => "blocked",
          "title" => "Compilation unavailable",
          "detail" =>
            "A saved configuration is required before runtime artifacts can be compiled.",
          "value" => nil
        }
      ]
    }
  end

  defp disable_action_props do
    %{
      "id" => "telemetry-decom-disable-button",
      "action_id" => "disable",
      "event" => "disable",
      "label" => "Disable workspace",
      "variant" => "secondary",
      "effect" => "durable",
      "execution" => "immediate",
      "confirmation" => %{
        "title" => "Disable application workspace?",
        "message" =>
          "Workspace access and configuration editing will stop. Existing configuration is retained, and active runtime state is unchanged until a separately governed mission change is applied.",
        "confirm_label" => "Disable workspace",
        "tone" => "attention",
        "prompt" =>
          "Disable application workspace?\n\nWorkspace access and configuration editing will stop. Existing configuration is retained, and active runtime state is unchanged until a separately governed mission change is applied."
      },
      "disabled" => false
    }
  end

  defp enable_action_props(disabled) do
    %{
      "id" => "telemetry-decom-enable-button",
      "action_id" => "request_activation",
      "event" => "enable",
      "label" => "Request mission changes",
      "variant" => "primary",
      "effect" => "durable",
      "execution" => "approval_required",
      "confirmation" => %{
        "title" => "Request mission changes?",
        "message" =>
          "Submit the current application configuration for governed approval. It will not become live until an authorized approver accepts and executes the request.",
        "confirm_label" => "Request mission changes",
        "tone" => "attention",
        "prompt" =>
          "Request mission changes?\n\nSubmit the current application configuration for governed approval. It will not become live until an authorized approver accepts and executes the request."
      },
      "disabled" => disabled
    }
  end

  defp assert_json_safe(vue) do
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
  end
end
