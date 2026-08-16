defmodule CadenceWeb.ControlPlaneApiFixtures do
  @moduledoc false

  import ExUnit.Assertions
  import Plug.Conn

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact, TransportBinding}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  def bootstrap(conn) do
    organization =
      Organization.new(%{
        organization_id: "org-alpha",
        slug: "org-alpha",
        display_name: "Org Alpha"
      })

    assert {:ok, organization} = Cadence.Organizations.persist_organization(organization)

    mission =
      Mission.new(%{
        mission_id: "mission-alpha",
        organization_id: organization.organization_id,
        slug: "mission-alpha",
        display_name: "Mission Alpha"
      })

    assert {:ok, mission} = Cadence.Missions.persist_mission(mission)

    service_identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-bootstrap",
        organization_id: organization.organization_id,
        display_name: "Control Plane Test Service",
        capabilities: [:organization_admin]
      })

    assert {:ok, %{api_token: api_token}} = Cadence.Auth.issue_service_identity(service_identity)

    %{
      conn: conn,
      api_token: api_token,
      organization_id: organization.organization_id,
      mission_id: mission.mission_id
    }
  end

  def authorize(conn, api_token) do
    put_req_header(conn, "authorization", "Bearer " <> api_token)
  end

  def organization_admin_scope(organization_id) when is_binary(organization_id) do
    assert {:ok, organization} = Cadence.Organizations.fetch_organization(organization_id)
    user = TestFixtures.persist_user!()
    _membership = TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    session_token = TestFixtures.member_session_token!(user)

    assert {:ok, scope} =
             Cadence.Auth.authenticate_browser_session(session_token,
               current_organization_id: organization_id
             )

    scope
  end

  def fetch_command_id(runtime_plans, command_name) do
    runtime_plans.command.plan["runtime_definitions"]
    |> Enum.find(&(&1["name"] == command_name))
    |> Map.fetch!("command_id")
  end

  def compile_and_approve_empty_mission_model!(organization_id, mission_id) do
    layer =
      Layer.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        name: "Control-plane activation model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    assert {:ok, compilation} = Cadence.MissionModels.compile_layers([layer])

    assert {:ok, revision} =
             Cadence.MissionModels.approve_revision(
               organization_id,
               mission_id,
               compilation.revision.revision_id,
               %{"kind" => "test_fixture", "id" => "control-plane-api"}
             )

    revision
  end

  def seed_mission_read_models(organization_id, mission_id) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-001",
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: "SC-001"
      })

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-endpoint-read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: "spacecraft-001",
        source_ref: "sc-001",
        display_name: "SC-001"
      })

    packet_definition =
      PacketDefinition.new(%{
        packet_definition_id: "packet-def-read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        packet_name: "HK",
        apid: 42,
        fields: [
          %{
            field_id: "field-counter",
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          },
          %{
            field_id: "field-voltage",
            name: "voltage",
            offset_bits: 16,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        binding_set_id: "read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "tm-apid-42",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    counter_limit =
      LimitDefinition.new(%{
        mission_id: mission_id,
        limit_definition_id: "counter-limit-read-models",
        point_id: "HK.counter",
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 20}
      })

    voltage_limit =
      LimitDefinition.new(%{
        mission_id: mission_id,
        limit_definition_id: "voltage-limit-read-models",
        point_id: "HK.voltage",
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 100}
      })

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-contact-read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [source_endpoint.source_endpoint_id],
        starts_at: DateTime.from_unix!(1_700_090_000, :second),
        ends_at: DateTime.from_unix!(1_700_090_600, :second),
        paths: contact_paths(source_endpoint.source_endpoint_id)
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint)

    assert {:ok, persisted_binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert {:ok, ^counter_limit} = Cadence.Limits.persist_limit_definition(counter_limit)
    assert {:ok, ^voltage_limit} = Cadence.Limits.persist_limit_definition(voltage_limit)

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_contact} =
             Cadence.Contacts.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "weather"
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(mission_id, "sc-001", 30, 50, 1_700_090_100),
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version
             )

    assert {:ok, _mission} = Cadence.Missions.fetch_mission(organization_id, mission_id)
    assert {:ok, limit_run} = Cadence.Limits.evaluate(mission_id, [])
    assert limit_run.status == :completed
  end

  def contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "uplink-path-read-models",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "downlink-path-read-models",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  def persist_active_uplink_contact_for_command_release(
        organization_id,
        mission_id,
        source_endpoint_ref
      ) do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-commanding-" <> Integer.to_string(System.unique_integer([:positive])),
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_410_000, :second),
        paths: [
          Path.new(%{
            path_id: "uplink-path-commanding-api",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: source_endpoint_ref,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-gateway-commanding-api",
                family_key: :uplink_gateway,
                target_scope: :path,
                configuration: %{"service_name" => "gateway"}
              })
            ]
          })
        ]
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.Contacts.persist_realized_contact(organization_id, realized_contact)

    assert {:ok, _pid} =
             Cadence.Contacts.start_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    realized_contact
  end

  def raw_evidence_fixture(mission_id, source_ref, counter_value, voltage_value, receipt_unix) do
    RawEvidence.new(%{
      mission_id: mission_id,
      source_ref: source_ref,
      receipt_time: DateTime.from_unix!(receipt_unix, :second),
      raw: build_space_packet(42, 1, <<counter_value::16, voltage_value::16>>)
    })
  end

  def build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end

  def build_tm_single_frame(apid, sequence_count, packet_data, frame_size) do
    packet = build_space_packet(apid, sequence_count, packet_data)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init(vcfc: 0)

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, ocf_length: 0},
        segmentation_state,
        []
      )

    <<encoded_frame::binary-size(^frame_size), _rest::binary>> = encoded_frames
    encoded_frame
  end
end
