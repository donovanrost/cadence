defmodule Cadence.Applications.SpacecraftConfiguration.DraftsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Reads.Spacecraft.Configuration, as: ConfigurationRead
  alias Cadence.Reads.Spacecraft.ConfigurationCatalogs

  alias Cadence.Applications.{HostContext, TelemetryDecomFixtures}
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput
  alias Cadence.Reads.Applications.SpacecraftInventory
  alias Cadence.Reads.Catalog.SpacecraftUsage

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

  test "spacecraft applications can be discovered without a profile", c do
    assert c.spacecraft.spacecraft_type_id == nil

    assert {:ok, items} =
             SpacecraftInventory.load(
               c.scope,
               HostContext.spacecraft(c.mission.mission_id, c.spacecraft.spacecraft_id)
             )

    assert Enum.any?(items, &(&1.application_key == "telemetry_decom" and &1.installable?))
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

  test "catalog usage finds matching spacecraft beyond the first fleet page and excludes superseded bindings",
       c do
    {:ok, spacecraft} =
      Cadence.SpacecraftStore.persist_spacecraft(c.org, %{
        c.spacecraft
        | spacecraft_id: "zz-spacecraft-catalog-usage"
      })

    c = %{c | spacecraft: spacecraft}

    for index <- 1..100 do
      TelemetryDecomFixtures.persist_spacecraft!(c.org, c.mission.mission_id,
        display_name: "Aardvark #{index}"
      )
    end

    craft_id = c.spacecraft.spacecraft_id
    catalog_id = c.revision.catalog_revision_id

    page =
      Cadence.SpacecraftStore.list_spacecraft_page(c.org, c.mission.mission_id, page_size: 100)

    refute Enum.any?(page.items, &(&1.spacecraft_id == craft_id))

    before = ConfigurationDrafts.snapshot(c.mission, c.spacecraft)
    document = %{ConfigurationInput.empty() | "catalog_revision_id" => catalog_id}
    assert {:ok, _} = save(c, before.token, document)

    assert {:ok, %{usage: [%{id: ^craft_id, active: false, saved: true}]}} =
             SpacecraftUsage.load(c.mission, catalog_id)

    latest = ConfigurationDrafts.snapshot(c.mission, c.spacecraft)
    assert {:ok, _} = save(c, latest.token, ConfigurationInput.empty())

    assert {:ok, %{usage: []}} =
             SpacecraftUsage.load(c.mission, catalog_id)
  end

  test "usage totals include every saved spacecraft and disclose the bounded detail list", c do
    for index <- 1..101 do
      craft =
        TelemetryDecomFixtures.persist_spacecraft!(c.org, c.mission.mission_id,
          display_name: "Saved craft #{index}"
        )

      before = ConfigurationDrafts.snapshot(c.mission, craft)

      assert {:ok, _} =
               save(%{c | spacecraft: craft}, before.token, %{
                 ConfigurationInput.empty()
                 | "catalog_revision_id" => c.revision.catalog_revision_id
               })
    end

    assert {:ok, snapshot} = SpacecraftUsage.snapshot(c.mission)

    assert SpacecraftUsage.summary(snapshot, [c.revision.catalog_revision_id]) ==
             %{active_count: 0, saved_count: 101}

    assert {:ok, %{total_count: 101, usage: rows}} =
             SpacecraftUsage.load(c.mission, c.revision.catalog_revision_id)

    assert length(rows) == 100
    assert Enum.all?(rows, &(&1.saved and not &1.active))
  end

  test "usage excludes saved configurations in other missions and organizations", c do
    for {org, mission_id} <- [{c.org, "other-mission"}, {"other-org", "other-org-mission"}] do
      {craft, revision, _endpoint} =
        TelemetryDecomFixtures.setup_imported_mission!(org, mission_id)

      {:ok, mission} = Cadence.Missions.fetch_mission(org, mission_id)
      scope = TelemetryDecomFixtures.user_scope(org, "other")
      before = ConfigurationDrafts.snapshot(mission, craft)

      assert {:ok, _} =
               ConfigurationDrafts.save(scope, mission_id, craft.spacecraft_id, before.token, %{
                 ConfigurationInput.empty()
                 | "catalog_revision_id" => revision.catalog_revision_id
               })

      assert {:ok, snapshot} = SpacecraftUsage.snapshot(c.mission)

      assert SpacecraftUsage.summary(snapshot, [revision.catalog_revision_id]) ==
               %{active_count: 0, saved_count: 0}
    end
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
