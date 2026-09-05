defmodule CadenceWeb.SpacecraftTelemetryDecomLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    SurfaceQueryRequest,
    TelemetryDecom
  }

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, State, Update}
  alias CadenceWeb.TestFixtures

  test "authenticated manage mount exposes the trusted federated surface" do
    {conn, _scope, _org, mission, spacecraft} = setup_session()

    {:ok, view, _html} = live(conn, manage_path(mission, spacecraft))

    assert has_element?(
             view,
             "#spacecraft-application-host[data-application-key='telemetry_decom'][data-application-version='1'][data-surface-id='manage']"
           )

    host = LiveVue.Test.get_vue(view, id: "application-host-component")
    assert host.component == "ApplicationHost"
    assert host.handlers == %{}
    assert_federated_descriptor(view, mission, spacecraft)
  end

  test "Manage saves catalog context through the retained domain handler" do
    {conn, _scope, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} = live(conn, manage_path(mission, spacecraft))
    render_hook(view, "save_catalog_revision", %{})

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

    assert_federated_descriptor(view, mission, spacecraft)
  end

  test "Packet Bindings query is authorized and scoped to the installed spacecraft subject" do
    {_conn, scope, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    request = %SurfaceQueryRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      surface_id: "packet_bindings",
      surface_version: 1,
      query_id: "cadence.packet_bindings.manage",
      query_version: 1
    }

    assert {:ok, document} =
             Cadence.Reads.ApplicationSurfaces.PacketBindings.load(scope, host_context, request)

    groups = document.packet_bindings.packet_groups

    assert [group] = groups
    assert group.apid == 42
    assert group.packet_name == "HEALTH"

    assert Enum.any?(
             group.resources,
             &(&1.resource_kind == :field and &1.path =~ "mode")
           )

    assert {:error, :application_not_installed} =
             Cadence.Reads.ApplicationSurfaces.PacketBindings.load(
               scope,
               HostContext.spacecraft(mission.mission_id, "other-spacecraft"),
               request
             )
  end

  test "disable rolls back the enabled flag through the retained event" do
    {conn, _scope, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} = live(conn, manage_path(mission, spacecraft))
    render_hook(view, "disable", %{"action-id" => "disable"})

    assert has_element?(view, "#flash-info", "Telemetry Decom disabled for this spacecraft.")

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
    {conn, _scope, org, mission, spacecraft} = setup_session()
    revision = persist_revision!(org, mission)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42]
             )

    {:ok, view, _html} = live(conn, manage_path(mission, spacecraft))
    render_hook(view, "enable", %{"action-id" => "request_activation"})

    assert has_element?(view, "#flash-info", "Telemetry Decom activation requested")

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(org.organization_id, mission.mission_id)

    {:ok, remounted_view, _html} = live(conn, manage_path(mission, spacecraft))
    assert_federated_descriptor(remounted_view, mission, spacecraft)
  end

  test "switching catalog revision clears the retained APID selection" do
    {conn, _scope, org, mission, spacecraft} = setup_session()
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

    {:ok, view, _html} = live(conn, manage_path(mission, spacecraft))
    render_hook(view, "change_revision", %{"catalog_revision_id" => rev_b.catalog_revision_id})

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.catalog_revision_id == rev_b.catalog_revision_id
    assert config.handled_apids == []
    assert_federated_descriptor(view, mission, spacecraft)
  end

  test "spacecraft show mount exposes its route-owned descriptor" do
    {conn, _scope, _org, mission, spacecraft} = setup_session()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

    assert has_element?(view, "#spacecraft-show-component")
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-show-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
             "surface_id" => "show",
             "host_scope" => "spacecraft",
             "mission_id" => mission.mission_id,
             "spacecraft_id" => spacecraft.spacecraft_id,
             "query_params" => %{
               "mission_id" => mission.mission_id,
               "spacecraft_id" => spacecraft.spacecraft_id
             }
           }
  end

  test "unauthenticated telemetry routes redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(
               conn,
               "/missions/mission-test/spacecraft/spacecraft-test/applications/telemetry_decom/manage"
             )
  end

  defp assert_federated_descriptor(view, mission, spacecraft) do
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-telemetry-decom-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
             "surface_id" => "telemetry_decom",
             "host_scope" => "spacecraft",
             "mission_id" => mission.mission_id,
             "spacecraft_id" => spacecraft.spacecraft_id,
             "query_params" => %{
               "mission_id" => mission.mission_id,
               "spacecraft_id" => spacecraft.spacecraft_id
             }
           }
  end

  defp manage_path(mission, spacecraft) do
    ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom/manage"
  end

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

    {TestFixtures.member_conn(user), scope, org, mission, spacecraft}
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
      Keyword.get(opts, :yaml, """
      packets:
        - name: HEALTH
          apid: 42
          items:
            - name: mode
              data_type: uint
              bit_offset: 0
              bit_size: 8
      commands: []
      """)

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
          Enum.map(
            result.parameter_updates,
            &{&1.parameter_id, &1.value, &1.quality, &1.generation_time, &1.receipt_time}
          ),
        monitoring:
          Enum.map(
            result.monitoring_results,
            &{&1.policy_id, &1.parameter_id, &1.effective_state, &1.transition}
          )
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

  defp installation_read_scope(organization_id) do
    %Scope{
      actor_kind: :user,
      organization_id: organization_id,
      user: %{},
      capabilities: MapSet.new([:platform_admin])
    }
  end
end
