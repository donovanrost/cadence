defmodule Cadence.Runtime.TCPSocketBackpressureTest do
  @moduledoc """
  11-14 00:38:36–00:40:40Z, end to end: frames that arrive while persistence is held are all kept,
  each with its own receipt time and identity (docs/apogee/plans/ingress-time-tags.md, #83). The
  merge itself is pinned in `IngressJournalTimeTagsTest`: running contacts take the journal policy
  captured at boot, and config/test.exs takes one record per batch.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow
  alias Cadence.Telemetry.Storage.ObservationIdentityStates
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  @frame_size 14

  test "frames that arrive while persistence is held are all kept, each with its own time and identity" do
    %{mission_id: mission_id, port: port} = start_tcp_contact!()
    test_pid = self()
    handler = "tcp-backpressure-#{System.unique_integer([:positive])}"

    # Hold the journal consumer on its first batch, as slow persistence did.
    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :ingress_journal, :processing_batch],
        fn _event, %{entries: entries}, _metadata, _config ->
          send(test_pid, {:processing_batch, self(), entries})

          if Process.get(:backpressure_held?) != true do
            Process.put(:backpressure_held?, true)

            receive do
              :release_consumer -> :ok
            after
              5_000 -> :ok
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)

    assert :ok = :gen_tcp.send(socket, frame(100))
    assert_receive {:processing_batch, consumer, 1}, 2_000

    # Seven more frames, each its own socket read and journal record, while the consumer waits.
    for count <- 101..107 do
      assert :ok = :gen_tcp.send(socket, frame(count))
      Process.sleep(50)
    end

    send(consumer, :release_consumer)

    rows =
      wait_for_rows(mission_id, 8)
      |> Enum.sort_by(& &1.receipt_time, DateTime)

    assert length(rows) == 8, "no frame may be lost"
    times = Enum.map(rows, & &1.receipt_time)
    assert length(Enum.uniq(times)) == 8, "each frame keeps its own receipt time"
    assert Enum.map(rows, & &1.generation_time) == times
    assert DateTime.diff(List.last(times), Enum.at(times, 1), :millisecond) >= 250

    assert mission_id
           |> ObservationIdentityStates.list_for_selection()
           |> length() == 8
  end

  defp wait_for_rows(mission_id, expected, attempts \\ 40) do
    rows =
      TelemetrySampleRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.all()

    if length(rows) >= expected or attempts == 0 do
      rows
    else
      Process.sleep(50)
      wait_for_rows(mission_id, expected, attempts - 1)
    end
  end

  defp frame(sequence_count) do
    packet = <<0::3, 0::1, 0::1, 42::11, 3::2, sequence_count::14, 1::16, 0, 4>>

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

    {:ok, state} = Segmentation.init([])

    {:ok, encoded, _state} =
      Segmentation.segment_encode(sdu, %{frame_size: @frame_size, ocf_length: 0}, state, [])

    encoded
  end

  defp start_tcp_contact! do
    id = Integer.to_string(System.unique_integer([:positive]))
    organization_id = "org-tcp-backpressure-" <> id
    mission_id = "mission-tcp-backpressure-" <> id
    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{spacecraft_id: "sc-bp-" <> id, mission_id: mission_id, display_name: "BP"})

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    {:ok, endpoint} =
      Cadence.SourceEndpoints.persist_source_endpoint(
        organization_id,
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-bp-" <> id,
          mission_id: mission_id,
          spacecraft_id: spacecraft.spacecraft_id,
          source_ref: "provider/tcp"
        })
      )

    activate_hk_binding!(organization_id, mission_id, id)
    contact = contact(organization_id, mission_id, endpoint.source_endpoint_id, id)
    {:ok, _} = Cadence.Contacts.persist_realized_contact(organization_id, contact)

    {:ok, _pid} =
      Cadence.Contacts.start_realized_contact(
        organization_id,
        mission_id,
        contact.realized_contact_id
      )

    {:ok, snapshot} =
      Cadence.path_runtime_snapshot(
        organization_id,
        mission_id,
        contact.realized_contact_id,
        "bp-downlink-" <> id
      )

    [provider] = snapshot.provider_runtimes
    %{mission_id: mission_id, port: provider.port}
  end

  defp activate_hk_binding!(organization_id, mission_id, id) do
    definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-bp-" <> id,
        packet_name: "HK",
        apid: 42,
        version: 1,
        fields: [
          %{field_id: "mode", name: "sc_mode", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "bp-basis-" <> id,
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "bp-rule-" <> id,
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(organization_id, binding_set)

    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        organization_id,
        mission_id,
        persisted.binding_set_id,
        persisted.version,
        activated_by: %{"service_identity_id" => "svc-test"}
      )
  end

  defp contact(organization_id, mission_id, endpoint_id, id) do
    RealizedContact.new(%{
      realized_contact_id: "bp-contact-" <> id,
      organization_id: organization_id,
      mission_id: mission_id,
      source_endpoint_refs: [endpoint_id],
      clock_mode: :live,
      initial_time: DateTime.utc_now(),
      paths: [
        Path.new(%{
          path_id: "bp-uplink-" <> id,
          direction: :uplink,
          selection_role: :selected,
          source_endpoint_ref: endpoint_id
        }),
        Path.new(%{
          path_id: "bp-downlink-" <> id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: endpoint_id,
          provider_bindings: [
            ProviderBinding.new(%{
              provider_binding_id: "bp-provider-" <> id,
              adapter_key: :tcp_socket,
              configuration: %{
                mode: :listen,
                port: 0,
                ingress_protocol_family: :tm,
                frame_size: @frame_size,
                ingress_metadata: %{frame_size: @frame_size, ocf_length: 0}
              }
            })
          ]
        })
      ]
    })
  end
end
