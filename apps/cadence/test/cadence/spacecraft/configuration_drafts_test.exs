defmodule Cadence.Applications.SpacecraftConfiguration.DraftsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Reads.Spacecraft.Configuration, as: ConfigurationRead
  alias Cadence.Reads.Spacecraft.ConfigurationCatalogs

  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  setup do
    org = "org-spacecraft-config"
    mission_id = "mission-spacecraft-config"

    {spacecraft, revision, endpoint} =
      TelemetryDecomFixtures.setup_imported_mission!(org, mission_id)

    {:ok, mission} = Cadence.Missions.fetch_mission(org, mission_id)
    scope = TelemetryDecomFixtures.user_scope(org, "workspace")

    %{
      org: org,
      mission: mission,
      scope: scope,
      spacecraft: spacecraft,
      revision: revision,
      endpoint: endpoint
    }
  end

  test "workspace exposes scoped catalog choices, packets, and saved versions", c do
    assert {:ok, page} =
             ConfigurationRead.load(
               c.scope,
               c.mission,
               c.spacecraft.spacecraft_id,
               "catalog"
             )

    assert [%{id: catalog, packets: 1, commands: 0}] = page.catalogs
    assert catalog == c.revision.catalog_revision_id
    assert page.active == nil

    assert {:ok, %{packets: [%{apid: 42, name: "HEALTH"}]}} =
             ConfigurationCatalogs.packets(
               c.scope,
               c.mission.mission_id,
               c.spacecraft.spacecraft_id,
               catalog
             )
  end

  test "saves an incomplete immutable draft without activating runtime", c do
    before = ConfigurationDrafts.snapshot(c.mission, c.spacecraft)
    assert {:ok, saved} = save(c, before.token, ConfigurationInput.empty())
    assert saved.version == 1
    assert saved.catalog_revision_id == nil

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    after_save = ConfigurationDrafts.snapshot(c.mission, c.spacecraft)
    assert after_save.saved == saved.document
    assert after_save.token != before.token
  end

  test "each spacecraft keeps its own catalog and stale saves cannot overwrite it", c do
    other =
      TelemetryDecomFixtures.persist_spacecraft!(c.org, c.mission.mission_id,
        display_name: "Second"
      )

    other_revision =
      TelemetryDecomFixtures.persist_imported_revision!(c.org, c.mission.mission_id,
        revision_label: "Second revision"
      )

    before = ConfigurationDrafts.snapshot(c.mission, c.spacecraft)

    document = %{
      ConfigurationInput.empty()
      | "catalog_revision_id" => c.revision.catalog_revision_id,
        "commanding_enabled" => true
    }

    assert {:ok, first} = save(c, before.token, document)
    other_before = ConfigurationDrafts.snapshot(c.mission, other)

    assert {:ok, second} =
             ConfigurationDrafts.save(
               c.scope,
               c.mission.mission_id,
               other.spacecraft_id,
               other_before.token,
               %{document | "catalog_revision_id" => other_revision.catalog_revision_id}
             )

    assert first.catalog_revision_id != second.catalog_revision_id

    assert {:error, :spacecraft_configuration_changed} =
             save(c, before.token, %{document | "commanding_enabled" => false})

    assert ConfigurationDrafts.latest(c.org, c.mission.mission_id, c.spacecraft.spacecraft_id).configuration_revision_id ==
             first.configuration_revision_id
  end

  test "rejects a packet source belonging to another spacecraft without persisting a draft", c do
    other =
      TelemetryDecomFixtures.persist_spacecraft!(c.org, c.mission.mission_id,
        display_name: "Second"
      )

    endpoint =
      TelemetryDecomFixtures.persist_source_endpoint!(
        c.org,
        c.mission.mission_id,
        other.spacecraft_id,
        display_name: "Other source"
      )

    before = ConfigurationDrafts.snapshot(c.mission, c.spacecraft)

    document = %{
      ConfigurationInput.empty()
      | "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_source_endpoint_id" => endpoint.source_endpoint_id,
        "telemetry_enabled" => true
    }

    assert {:error, :spacecraft_packet_input_unavailable} = save(c, before.token, document)

    assert ConfigurationDrafts.latest(c.org, c.mission.mission_id, c.spacecraft.spacecraft_id) ==
             nil
  end

  defp save(c, token, document),
    do:
      ConfigurationDrafts.save(
        c.scope,
        c.mission.mission_id,
        c.spacecraft.spacecraft_id,
        token,
        document
      )
end
