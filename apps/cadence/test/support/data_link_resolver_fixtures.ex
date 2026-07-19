defmodule Cadence.Dashboards.DataLinkResolverFixtures do
  @moduledoc false

  import Cadence.DataCase, only: [persist_mission_scope: 2]
  import ExUnit.Assertions

  alias Cadence.Comms.TransportStore

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Revision
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{Path, RealizedContact}
  alias Cadence.Ingress.RawEvidence

  alias Cadence.Persistence.Schemas.TelemetrySampleRow
  alias Cadence.Repo
  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  def persist_sample_scope!(suffix, value) do
    organization_id = "org-#{suffix}"
    mission_id = "mission-#{suffix}"
    spacecraft_id = "sc-#{suffix}"
    persist_mission_scope(organization_id, mission_id)
    binding_set = persist_binding_set!(organization_id, mission_id)
    activate_binding_set!(organization_id, mission_id, binding_set)
    ingest!(mission_id, binding_set, spacecraft_id, value)

    sample = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_id: spacecraft_id,
      sample_id: sample.sample_id,
      evidence_id: sample.evidence_id
    }
  end

  def persist_comparison_samples!(suffix) do
    organization_id = "org-#{suffix}"
    mission_id = "mission-#{suffix}"
    spacecraft_id = "sc-#{suffix}"
    persist_mission_scope(organization_id, mission_id)
    binding_set = persist_binding_set!(organization_id, mission_id)
    activate_binding_set!(organization_id, mission_id, binding_set)

    ingest!(
      mission_id,
      binding_set,
      spacecraft_id,
      41,
      receipt_time: ~U[2026-06-20 12:00:00Z],
      sequence_count: 1
    )

    primary = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])

    ingest!(
      mission_id,
      binding_set,
      spacecraft_id,
      42,
      receipt_time: ~U[2026-06-20 12:01:00Z],
      sequence_count: 2
    )

    compare = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      primary_sample_id: primary.sample_id,
      compare_sample_id: compare.sample_id
    }
  end

  def attach_storage_provenance!(sample_id, storage) do
    sample_row = Repo.get!(TelemetrySampleRow, sample_id)

    sample_row
    |> Ecto.Changeset.change(provenance: %{"storage" => storage})
    |> Repo.update!()
  end

  def persist_binding_set!(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "#{mission_id}-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted} = Cadence.Governance.persist_binding_set(organization_id, binding_set)
    persisted
  end

  def activate_binding_set!(organization_id, mission_id, binding_set) do
    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               []
             )
  end

  def ingest!(mission_id, binding_set, spacecraft_id, value, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: Keyword.get(opts, :receipt_time, ~U[2026-06-20 12:00:00Z]),
        raw: build_space_packet(42, Keyword.get(opts, :sequence_count, 1), <<value::16>>)
      })

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               evidence,
               binding_set.binding_set_id,
               binding_set.version
             )
  end

  def build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  def application_binding_set(mission_id, binding_set_id, opts) do
    source_endpoint_ref = Keyword.fetch!(opts, :source_endpoint_ref)
    apid = Keyword.fetch!(opts, :apid)
    metric_name = Keyword.fetch!(opts, :metric_name)

    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "#{binding_set_id}-packet-counter",
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => metric_name,
              "flush_interval_ms" => 25
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "#{binding_set_id}-packet-counter-rule",
          capability_instance_id: "#{binding_set_id}-packet-counter",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: apid}
          },
          priority: 10,
          fanout_mode: :multi
        })
      ]
    })
  end

  def catalog_revision(organization_id, mission_id, catalog_revision_id, opts) do
    Revision.new(%{
      catalog_revision_id: catalog_revision_id,
      organization_id: organization_id,
      mission_id: mission_id,
      catalog_database_id: "bus-catalog",
      revision_number: Keyword.fetch!(opts, :revision_number),
      revision_label: Keyword.fetch!(opts, :revision_label),
      catalog_family: :telemetry,
      artifact_id: "#{catalog_revision_id}-artifact",
      import_run_id: Keyword.fetch!(opts, :import_run_id),
      telemetry_snapshot_id: Keyword.fetch!(opts, :telemetry_snapshot_id),
      command_snapshot_id: nil,
      content_sha256: "#{catalog_revision_id}-sha",
      created_by: %{"service_identity_id" => "svc-importer"},
      metadata: %{"source_artifact_name" => "#{catalog_revision_id}.json"}
    })
  end

  def transport_capability_record(
        mission_id,
        transport_record_id,
        capability_instance_id,
        event_kind,
        recorded_at,
        opts
      ) do
    %TransportCapabilityRecord{
      transport_record_id: transport_record_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: capability_instance_id,
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      event_kind: event_kind,
      timer_key: Keyword.get(opts, :timer_key),
      emitted_record_kinds: Keyword.get(opts, :emitted_record_kinds, []),
      emitted_record_count: Keyword.get(opts, :emitted_record_count, 0),
      action_request_count: Keyword.get(opts, :action_request_count, 0),
      state_snapshot: Keyword.fetch!(opts, :state_snapshot),
      recorded_at: recorded_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def transport_action_request(
        mission_id,
        action_request_id,
        capability_instance_id,
        action_kind,
        requested_at,
        opts
      ) do
    %TransportActionRequest{
      action_request_id: action_request_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: capability_instance_id,
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      command_release_attempt_id:
        Keyword.get(opts, :command_release_attempt_id, "release-attempt-1"),
      command_request_id: Keyword.get(opts, :command_request_id, "command-request-1"),
      source_endpoint_ref: Keyword.get(opts, :source_endpoint_ref, "source-endpoint-alpha"),
      command_name: Keyword.get(opts, :command_name, "NOOP"),
      signal_phase: Keyword.get(opts, :signal_phase, :start),
      action_kind: action_kind,
      request_document: Keyword.fetch!(opts, :request_document),
      requested_at: requested_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def persist_source_endpoint_scope(organization_id, mission_id, source_endpoint_ref) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: "SC-001"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_ref,
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: "sc-001",
        source_ref: "provider/#{source_endpoint_ref}"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint)
  end

  def persist_transport_execution_scope(organization_id, mission_id) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        transport_id: "uplink-heartbeat",
        display_name: "Uplink Heartbeat",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      })

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-contact-1",
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        clock_mode: :replay,
        lifecycle_state: :active,
        initial_time: ~U[2026-06-30 12:00:00Z],
        realized_at: ~U[2026-06-30 12:00:00Z],
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha"
          })
        ]
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(organization_id, transport)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(organization_id, realized_contact)
  end

  def contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "resolver-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "resolver-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  def row_value(rows, label) do
    rows
    |> Enum.find(&(&1.label == label))
    |> Map.fetch!(:value)
  end

  def related_link(links, target, target_id) do
    Enum.find(links, &(&1.target == target and &1.target_id == target_id))
  end

  def action_for(actions, target) do
    Enum.find(actions, &(&1.target == target))
  end
end
