defmodule Cadence.Runtime.ProviderIngressObservabilityIntegrationTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence

  alias Cadence.Runtime.{
    IngressPersistenceProjector,
    ProviderIngressExecutor
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  test "processes and persists provider telemetry across both asynchronous boundaries" do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-provider-ingress-trace-" <> suffix
    source_ref = "provider/station-trace-" <> suffix

    on_exit(fn -> Cadence.Runtime.stop_mission(mission_id) end)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-provider-ingress-trace-" <> suffix,
        mission_id: mission_id,
        display_name: "Provider ingress trace spacecraft"
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-provider-ingress-trace-" <> suffix,
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: source_ref
      })

    assert {:ok, _source_endpoint} = Cadence.persist_source_endpoint(source_endpoint)

    binding_set = persist_binding_set(mission_id)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    projector_name = :"provider_ingress_trace_projector_#{suffix}"
    executor_name = :"provider_ingress_trace_executor_#{suffix}"

    start_supervised!(
      {IngressPersistenceProjector,
       name: projector_name,
       mission_id: mission_id,
       realized_contact_id: "contact-provider-ingress-trace-" <> suffix,
       path_id: "path-provider-ingress-trace-" <> suffix,
       provider_binding_id: "provider-binding-ingress-trace-" <> suffix}
    )

    start_supervised!(
      {ProviderIngressExecutor,
       name: executor_name,
       mission_id: mission_id,
       realized_contact_id: "contact-provider-ingress-trace-" <> suffix,
       path_id: "path-provider-ingress-trace-" <> suffix,
       provider_binding_id: "provider-binding-ingress-trace-" <> suffix,
       persistence_projector_name: projector_name}
    )

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-provider-ingress-trace-" <> suffix,
        mission_id: mission_id,
        source_ref: source_ref,
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert :ok = ProviderIngressExecutor.enqueue_telemetry(executor_name, raw_evidence)

    assert eventually(fn ->
             {:ok, executor_snapshot} = ProviderIngressExecutor.snapshot(executor_name)
             {:ok, projector_snapshot} = IngressPersistenceProjector.snapshot(projector_name)

             executor_snapshot.processed_count == 1 and
               executor_snapshot.failed_count == 0 and
               projector_snapshot.persisted_count == 1 and
               projector_snapshot.failed_count == 0
           end)
  end

  defp persist_binding_set(mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "provider-ingress-trace-packet",
        packet_name: "TRACE",
        apid: 42,
        version: 1,
        fields: [
          %{
            field_id: "counter",
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "provider-ingress-trace-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "provider-ingress-trace-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted_binding_set} = Cadence.persist_binding_set(binding_set)
    persisted_binding_set
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
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

  defp eventually(fun, attempts_left \\ 100)

  defp eventually(fun, attempts_left) when attempts_left > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts_left - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
