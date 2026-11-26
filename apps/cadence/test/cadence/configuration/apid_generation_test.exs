defmodule Cadence.Configuration.ApidGenerationTest do
  @moduledoc "Handled APIDs as a profile/override field (L22): nil = all of the catalog's APIDs."
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.CompositionFixtures
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations

  @two_apids """
  packets:
    - name: HEALTH
      apid: 42
      items:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_size: 8
    - name: POWER
      apid: 43
      items:
        - name: volts
          data_type: uint
          bit_offset: 0
          bit_size: 8
  commands: []
  """

  @other_apid """
  packets:
    - name: THERMAL
      apid: 50
      items:
        - name: temp
          data_type: uint
          bit_offset: 0
          bit_size: 8
  commands: []
  """

  setup do
    # The APID HOLDs and reader are configured in config.exs after the 11-14 freeze; until then
    # the test registers them.
    kinds = Application.get_env(:cadence, :configuration_kinds)
    apids = Application.get_env(:cadence, :catalog_apids)

    Application.put_env(
      :cadence,
      :configuration_kinds,
      Enum.uniq(kinds ++ [Cadence.Spacecraft.ConfigKinds.ApidCompatibility])
    )

    Application.put_env(:cadence, :catalog_apids, Cadence.MissionModels.CatalogApids)

    on_exit(fn ->
      Application.put_env(:cadence, :configuration_kinds, kinds)

      if apids,
        do: Application.put_env(:cadence, :catalog_apids, apids),
        else: Application.delete_env(:cadence, :catalog_apids)
    end)

    org = "org-apid-gen-#{System.unique_integer([:positive])}"
    mid = "mission-apid-gen-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    configure(scope, mission, craft, revision.catalog_revision_id)
    two = Fixtures.persist_imported_revision!(org, mid, revision_label: "Two", yaml: @two_apids)

    other =
      Fixtures.persist_imported_revision!(org, mid, revision_label: "Other", yaml: @other_apid)

    %{
      org: org,
      mission: mission,
      scope: scope,
      craft: craft,
      two: two.catalog_revision_id,
      other: other.catalog_revision_id
    }
  end

  test "all of the catalog's APIDs widens decode only with a HOLD saying so", c do
    {:ok, staged} = stage(c, pin_ops(c, profile_op("profile-apids-all", pin(c, c.two), nil)))

    assert {:ok, %{checks: checks}} =
             Configuration.preview(c.scope, c.mission.mission_id, staged.change_set_id)

    assert %{blocking: false, sentence: sentence} =
             checks
             |> Enum.flat_map(& &1.items)
             |> Enum.find(&(&1[:reason] == :handled_apids_change))

    assert sentence ==
             "#{c.craft.display_name} will also decode APIDs 0x2B after this is applied " <>
               "(today only 0x2A)."

    assert {:ok, %{state: :applied}} = submit(c, staged)
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    assert entry["document"]["handled_apids"] == [42, 43]
  end

  test "a list naming APIDs the catalog doesn't define is a field error", c do
    # A field error in the preview's validation (422 details.handled_apids through the API).
    {:ok, bad} = stage(c, [profile_op("profile-apids-bad", pin(c, c.two), [42, 99])])

    assert {:ok, %{checks: checks}} =
             Configuration.preview(c.scope, c.mission.mission_id, bad.change_set_id)

    assert %{verdict: verdict, items: items} = Enum.find(checks, &(&1.key == "validation"))
    assert verdict != :go
    assert Enum.any?(items, &(inspect(&1) =~ "doesn't define APIDs 99"))
  end

  test "a catalog move that leaves listed APIDs undefined is a blocking HOLD", c do
    # Pinned on [42] (valid in rev Two), then the profile moves to a catalog without 42.
    apply!(c, pin_ops(c, profile_op("profile-apids-42", pin(c, c.two), [42])))

    {:ok, staged} =
      stage(c, [
        %{
          kind: "spacecraft_override",
          action: :update,
          entity_id: c.craft.spacecraft_id,
          changes: [%{path: "composition_id", value: %{"value" => pin(c, c.other)}}]
        }
      ])

    assert {:ok, %{checks: checks}} =
             Configuration.preview(c.scope, c.mission.mission_id, staged.change_set_id)

    assert %{blocking: true, sentence: sentence} =
             checks
             |> Enum.flat_map(& &1.items)
             |> Enum.find(&(&1[:reason] == :handled_apids_not_in_catalog))

    assert sentence =~ "handles APIDs 0x2A, which rev "
    assert {:error, {:holds_blocking, _preview}} = submit(c, staged)
  end

  defp pin(c, catalog), do: CompositionFixtures.pin!(c.org, c.mission.mission_id, catalog)

  defp profile_op(id, composition, apids) do
    %{
      kind: "spacecraft_profile",
      action: :create,
      entity_id: id,
      document:
        Map.merge(
          %{
            "display_name" => "APID profile #{id}",
            "downlink_protocol" => "tm",
            "uplink_protocol" => "tc",
            "composition_id" => composition,
            "frame_parameters" => %{"frame_size" => 1115, "ocf_length" => 4}
          },
          if(apids, do: %{"handled_apids" => apids}, else: %{})
        )
    }
  end

  defp pin_ops(c, profile) do
    [
      profile,
      %{
        kind: "spacecraft",
        action: :update,
        entity_id: c.craft.spacecraft_id,
        changes: [
          %{path: "spacecraft_type_id", value: profile.entity_id},
          %{path: "spacecraft_type_version", value: 1}
        ]
      }
    ]
  end

  defp stage(c, ops),
    do: Configuration.stage(c.scope, c.mission.mission_id, %{summary: "APIDs"}, ops)

  defp apply!(c, ops) do
    {:ok, staged} = stage(c, ops)
    {:ok, %{state: :applied}} = submit(c, staged)
  end

  defp submit(c, staged) do
    Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
      reason: "APID generation test",
      expected_version: staged.version,
      acknowledged_holds: true
    })
  end

  defp configure(scope, mission, craft, catalog) do
    current = Drafts.snapshot(mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    {:ok, _} =
      Drafts.save(scope, mission.mission_id, craft.spacecraft_id, current.token, document)

    token = Drafts.snapshot(mission, craft).token

    {:ok, request} =
      Review.request_many(scope, mission.mission_id, %{craft.spacecraft_id => token})

    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end
end
