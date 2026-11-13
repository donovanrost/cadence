defmodule Cadence.Applications.SpacecraftConfigurationBasesTest do
  @moduledoc """
  A fleet's application bases, batched (`ApplicationInputs.bases/2`), are the per-spacecraft ones
  (`basis/2`) on a mixed fleet, and the scoped, batched packet reads return what the mission-wide,
  one-configuration-at-a-time reads did.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext, PacketBindings}
  alias Cadence.Applications.SpacecraftConfiguration.ApplicationInputs
  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.MissionModels.TelemetryProjection

  @org "org-configuration-bases"
  @mid "mission-configuration-bases"

  setup do
    {first, revision, _endpoint} = Fixtures.setup_imported_mission!(@org, @mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(@org, @mid)
    scope = Fixtures.user_scope(@org, "operator")
    {:ok, telemetry} = TelemetryProjection.load(@org, @mid, revision)
    packet = hd(telemetry.packet_definitions)

    c = %{mission: mission, scope: scope, revision: revision, packet: packet}

    crafts =
      Map.new(~w(packets_a packets_b telemetry_only telemetry_off untouched)a, fn name ->
        craft = Fixtures.persist_spacecraft!(@org, @mid, display_name: "#{name}")
        Fixtures.persist_source_endpoint!(@org, @mid, craft.spacecraft_id, display_name: "Down")
        {name, craft}
      end)

    for name <- [:packets_a, :packets_b, :telemetry_only], do: save(c, crafts[name], true)
    save(c, crafts.telemetry_off, false)
    save(c, first, true)

    # Two spacecraft with packet selections: bindings with resources, more than one config.
    for name <- [:packets_a, :packets_b], do: select_packets(c, crafts[name])

    Map.merge(c, %{fleet: [first | Map.values(crafts)], crafts: crafts})
  end

  test "batched bases equal each spacecraft's own basis on a mixed fleet", c do
    ids = Enum.map(c.fleet, & &1.spacecraft_id)
    batched = ApplicationInputs.bases(c.mission, ids)

    assert map_size(batched) == length(ids)
    assert batched == Map.new(ids, &{&1, ApplicationInputs.basis(c.mission, &1)})

    # A craft with packet selections differs from one without; the bases aren't all equal.
    assert batched[c.crafts.packets_a.spacecraft_id] !=
             batched[c.crafts.telemetry_only.spacecraft_id]

    assert ApplicationInputs.bases(c.mission, []) == %{}
  end

  test "scoped packet reads match the mission-wide read, one configuration at a time", c do
    all = PacketBindings.list_for_mission(@org, @mid, application_key: "telemetry_decom")
    ids = [c.crafts.packets_a.spacecraft_id, c.crafts.packets_b.spacecraft_id]

    assert length(all) >= 2
    assert Enum.all?(all, &(&1.bindings != []))
    assert Enum.any?(all, fn config -> Enum.any?(config.bindings, &(&1.resources != [])) end)

    scoped =
      PacketBindings.list_for_mission(@org, @mid,
        application_key: "telemetry_decom",
        spacecraft_ids: ids
      )

    assert scoped == Enum.filter(all, &(&1.spacecraft_id in ids))

    # The same configurations, hydrated one installation at a time.
    one_at_a_time =
      Enum.flat_map(ids, fn id ->
        host = HostContext.spacecraft(@mid, id)

        {:ok, installation} =
          ApplicationInstallations.fetch_installed(c.scope, host, "telemetry_decom")

        {:ok, configs} =
          PacketBindings.list(c.scope, host, installation.application_installation_id)

        configs
      end)

    assert Enum.sort_by(scoped, & &1.packet_binding_configuration_id) ==
             Enum.sort_by(one_at_a_time, & &1.packet_binding_configuration_id)
  end

  defp save(c, craft, telemetry?) do
    current = Drafts.snapshot(c.mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_enabled" => telemetry?,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    assert {:ok, _} =
             Drafts.save(c.scope, @mid, craft.spacecraft_id, current.token, document)
  end

  defp select_packets(c, craft) do
    host = HostContext.spacecraft(@mid, craft.spacecraft_id)

    {:ok, installation} =
      ApplicationInstallations.fetch_installed(c.scope, host, "telemetry_decom")

    [endpoint | _] =
      Cadence.SourceEndpoints.list_source_endpoints(@org, @mid,
        spacecraft_id: craft.spacecraft_id
      )

    assert {:ok, _configuration} =
             PacketBindings.replace(c.scope, host, installation.application_installation_id, %{
               input_id: "telemetry-fields",
               input_version: 1,
               catalog_revision_id: c.revision.catalog_revision_id,
               source_endpoint_ref: endpoint.source_endpoint_id,
               selected_packet_ids: [c.packet.packet_definition_id]
             })
  end
end
