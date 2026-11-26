defmodule Cadence.SharedListenerFixtures do
  @moduledoc """
  Real contacts on one listen-mode provider profile with "listener" => "shared" (#87): a mission
  with an activated telemetry binding, spacecraft with SCIDs and their endpoints, scheduled passes
  on the shared profile, and peers that connect with a TM frame for a SCID.
  """

  import Cadence.DataCase, only: [persist_mission_scope: 2]

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Contacts
  alias Cadence.Contacts.{Path, ProviderBinding, ScheduledContact}
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  @frame_size 10
  @apid 42

  def adapter(ctx, scheduled) do
    key =
      {:provider_runtime, ctx.mission_id, run_id(scheduled),
       "downlink-" <> scheduled.scheduled_contact_id, ctx.profile_id}

    [{pid, _}] = Registry.lookup(ProcessNamespace.default().registry, key)
    pid
  end

  def received(ctx, scheduled) do
    path_id = "downlink-" <> scheduled.scheduled_contact_id

    case Cadence.Runtime.path_runtime_snapshot(ctx.mission_id, run_id(scheduled), path_id) do
      {:ok, snapshot} -> downlink_bytes(snapshot)
      _not_running -> 0
    end
  end

  defp downlink_bytes(%{downlink_bytes_received: bytes}) when is_integer(bytes), do: bytes

  defp downlink_bytes(map) when is_map(map),
    do: map |> Map.values() |> Enum.map(&downlink_bytes/1) |> Enum.sum()

  defp downlink_bytes(list) when is_list(list),
    do: list |> Enum.map(&downlink_bytes/1) |> Enum.sum()

  defp downlink_bytes(_other), do: 0

  def connect!(port, first) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, first)
    socket
  end

  # A TM transfer frame header for `scid`, padded to the frame size.
  def frame(scid), do: <<0::2, scid::10, 0::3, 0::1, 0::16, 0::16>> <> <<0::32>>

  def endpoint!(ctx, name, scid) do
    spacecraft_id = "sc-#{name}-#{System.unique_integer([:positive])}"

    {:ok, _} =
      Cadence.SpacecraftStore.persist_spacecraft(
        ctx.organization_id,
        Spacecraft.new(%{
          spacecraft_id: spacecraft_id,
          mission_id: ctx.mission_id,
          display_name: name,
          scid: scid
        })
      )

    {:ok, endpoint} =
      Cadence.SourceEndpointFixtures.persist(
        ctx.organization_id,
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-#{name}-#{System.unique_integer([:positive])}",
          mission_id: ctx.mission_id,
          spacecraft_id: spacecraft_id,
          source_ref: "provider/tcp/#{name}"
        })
      )

    endpoint.source_endpoint_id
  end

  def schedule!(ctx, endpoint_id, name, starts_at, ends_at, port, configuration \\ %{}) do
    id = "#{name}-#{System.unique_integer([:positive])}"

    contact =
      ScheduledContact.new(%{
        scheduled_contact_id: id,
        mission_id: ctx.mission_id,
        source_endpoint_refs: [endpoint_id],
        starts_at: starts_at,
        ends_at: ends_at,
        paths: [
          Path.new(%{
            path_id: "downlink-#{id}",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: ctx.profile_id,
                adapter_key: :tcp_socket,
                configuration:
                  Map.merge(
                    %{
                      mode: :listen,
                      listener: "shared",
                      port: port,
                      ingress_protocol_family: :tm,
                      frame_size: @frame_size,
                      ingress_metadata: %{frame_size: @frame_size, ocf_length: 0}
                    },
                    configuration
                  )
              })
            ]
          })
        ]
      })

    {:ok, scheduled} = Contacts.persist_scheduled_contact(ctx.organization_id, contact)
    scheduled
  end

  def run_id(%ScheduledContact{scheduled_contact_id: id}), do: id <> "_run"

  # The stopped acceptor's listener may still be closing: retry the bind briefly.
  def squat!(port, attempts \\ 40) do
    case :gen_tcp.listen(port, [:binary, ip: {127, 0, 0, 1}, reuseaddr: true]) do
      {:ok, socket} ->
        socket

      {:error, :eaddrinuse} when attempts > 0 ->
        Process.sleep(50)
        squat!(port, attempts - 1)
    end
  end

  def free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  def fixture! do
    organization_id = "org-start-#{System.unique_integer([:positive])}"
    suffix = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-start-" <> suffix
    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-start-" <> suffix,
        mission_id: mission_id,
        display_name: "SC start"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    {:ok, endpoint} =
      Cadence.SourceEndpointFixtures.persist(
        organization_id,
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-start-" <> suffix,
          mission_id: mission_id,
          spacecraft_id: spacecraft.spacecraft_id,
          source_ref: "provider/tcp"
        })
      )

    packet =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-start-" <> suffix,
        packet_name: "TMHK",
        apid: @apid,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    {:ok, binding_set} =
      Cadence.Governance.persist_binding_set(
        organization_id,
        BindingSet.new(%{
          mission_id: mission_id,
          binding_set_id: "start-basis-" <> suffix,
          version: 1,
          rules: [
            BindingRule.new(%{
              binding_rule_id: "start-telemetry-rule-" <> suffix,
              handler_key: :definition_bound_telemetry,
              packet_kind: :space_packet,
              apid: @apid,
              priority: 10,
              handler_configuration: packet
            })
          ]
        })
      )

    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        organization_id,
        mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        activated_by: %{"service_identity_id" => "svc-test"}
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      endpoint_id: endpoint.source_endpoint_id,
      profile_id: "provider-profile-" <> suffix
    }
  end
end
