defmodule Cadence.Configuration.FramingGenerationTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, TransportStore}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.{Configuration, ConfigurationRollback}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Platform.ConfigurationSettings
  alias Cadence.Runtime.SourceRuntimeBases

  setup do
    org = "org-framing-#{System.unique_integer([:positive])}"
    mid = "mission-framing-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    configure_legacy(scope, mission, craft, revision)
    %{org: org, mission: mission, scope: scope, craft: craft}
  end

  test "with the flag on, a profile framing change set becomes a profile-framed generation", c do
    {:ok, _} =
      ConfigurationSettings.put_profile_framing_generations(c.org, c.mission.mission_id, true, %{
        id: "test",
        name: "Test"
      })

    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert {:ok, %{state: :applied, generation: generation, runtime: runtime}} =
             apply_framing_profile(c, 1279)

    assert generation == before.generation + 1
    assert runtime in [:applied, :degraded]

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    assert entry["framing_authority"] == "profile"
    assert entry["framing"]["frame_size"] == 1279
    assert %{"change_set" => %{"spacecraft_ids" => [_]}} = active.metadata

    assert {:ok, spec} = Cadence.Runtime.Missions.applied_spec(c.mission.mission_id)
    [source | _] = entry["source_endpoint_ids"]

    assert {:ok, %{framing: %{"frame_size" => 1279}}} =
             SourceRuntimeBases.fetch(spec.source_runtime_bases, source)
  end

  test "rolling back a framing change produces a generation too (DECISIONS #49)", c do
    {:ok, _} =
      ConfigurationSettings.put_profile_framing_generations(c.org, c.mission.mission_id, true, %{
        id: "test",
        name: "Test"
      })

    assert {:ok, %{state: :applied, revision: on_first}} = apply_framing_profile(c, 1279)
    assert {:ok, %{state: :applied, generation: second}} = apply_framing_profile(c, 1024)

    # Back to the 1279 profile: the craft is re-pinned and the 1024 profile removed.
    assert {:ok, %{ops: ops}} =
             ConfigurationRollback.preview(
               c.scope,
               c.mission.mission_id,
               on_first
             )

    assert [
             %{kind: "spacecraft", action: "update"},
             %{kind: "spacecraft_profile", action: "delete"}
           ] =
             ops

    assert {:ok, staged} =
             ConfigurationRollback.stage(c.scope, c.mission.mission_id, on_first)

    assert {:ok, %{state: :applied, generation: generation, revision: revision}} =
             submit(c, staged)

    assert generation == second + 1

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    assert entry["framing"]["frame_size"] == 1279

    assert {:ok, %{kind: :rollback, rolls_back_to: ^on_first}} =
             Configuration.get_revision(c.scope, c.mission.mission_id, revision)
  end

  test "unpinning a profile-framed spacecraft hands framing back in a new generation", c do
    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    {:ok, before_entry} = FleetSnapshot.entry(before.metadata, c.craft.spacecraft_id)
    {:ok, %{state: :applied}} = apply_framing_profile(c, 1279)
    {:ok, pinned} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    {:ok, staged} =
      Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Unpin"}, [
        %{
          kind: "spacecraft",
          action: :update,
          entity_id: c.craft.spacecraft_id,
          changes: [
            %{path: "spacecraft_type_id", value: nil},
            %{path: "spacecraft_type_version", value: nil}
          ]
        }
      ])

    assert {:ok, %{state: :applied, generation: generation}} = submit(c, staged)
    assert generation == pinned.generation + 1

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    refute Map.has_key?(entry, "framing_authority")
    refute Map.has_key?(entry, "framing")
    # Back to the spacecraft's own configuration, exactly as before the pin.
    assert entry["document"]["protocol"] == before_entry["document"]["protocol"]
  end

  test "rolling back a pin hands framing back in a new generation (#49 with 0e5b17d4)", c do
    {:ok, _} =
      ConfigurationSettings.put_profile_framing_generations(c.org, c.mission.mission_id, true, %{
        id: "test",
        name: "Test"
      })

    assert {:ok, %{state: :applied, revision: pinned, generation: framed}} =
             apply_framing_profile(c, 1279)

    assert {:ok, staged} = ConfigurationRollback.stage(c.scope, c.mission.mission_id, pinned - 1)
    assert {:ok, %{state: :applied, generation: generation}} = submit(c, staged)
    assert generation == framed + 1

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    refute Map.has_key?(entry, "framing_authority")
  end

  describe "compatibility HOLD (qa #16)" do
    setup c do
      {:ok, _} =
        ConfigurationSettings.put_profile_framing_generations(
          c.org,
          c.mission.mission_id,
          true,
          %{
            id: "test",
            name: "Test"
          }
        )

      profile_id = "profile-hold-#{System.unique_integer([:positive])}"
      station = "station-#{System.unique_integer([:positive])}"
      transport_id = "transport-#{System.unique_integer([:positive])}"

      # A station and the TCP transport feeding the craft (ingress 1115 bytes, OCF 0), a profile
      # matching it, then the configured craft pinned to the profile.
      apply_ops!(c, [
        %{
          kind: "ground_station",
          action: :create,
          entity_id: station,
          document: %{"display_name" => "Svalbard", "code" => "SVB"}
        },
        %{
          kind: "transport",
          action: :create,
          entity_id: transport_id,
          document: feeding_transport(station)
        },
        create_profile(profile_id, 1115)
      ])

      route_craft(c, transport_id)
      apply_ops!(c, [pin(c.craft.spacecraft_id, profile_id)])
      %{profile_id: profile_id}
    end

    test "a profile frame_size change 1115 -> 1024 with rollout holds against the transport", c do
      edit = %{
        kind: "spacecraft_profile",
        action: :update,
        entity_id: c.profile_id,
        changes: [%{path: "frame_parameters.frame_size", value: 1024}],
        options: %{rollout: "all"}
      }

      assert {:ok, %{verdict: :hold, checks: checks}} =
               Configuration.preview(c.scope, c.mission.mission_id, {:ops, [edit]})

      assert %{verdict: :hold, items: [item | _]} =
               Enum.find(checks, &(&1.key == "compatibility"))

      assert %{
               reason: :framing_mismatch,
               entity_id: profile_id,
               profile_value: %{path: "frame_parameters.frame_size", value: 1024}
             } = item

      assert profile_id == c.profile_id
      # Same keys as validation and conflict items, so clients decode one item shape (qa #18).
      assert Map.has_key?(item, :change_id) and Map.has_key?(item, :op_id)
      assert item.transport_value.value == 1115
      # ux: a plain sentence with units; the raw comparison in detail.
      assert item.sentence =~ "would decode 1,024-byte frames, but"
      assert item.sentence =~ "sends 1,115-byte frames."

      assert item.detail =~
               "frame_parameters.frame_size = 1024 (profile) vs ingress_metadata.frame_size = 1115"
    end

    test "framing that can't be checked against a transport holds as framing_unverified", c do
      [rule] =
        RoutingRuleStore.list_routing_rules_for_spacecraft(
          c.org,
          c.mission.mission_id,
          c.craft.spacecraft_id
        )

      {:ok, _} =
        RoutingRuleStore.archive_routing_rule(
          c.org,
          c.mission.mission_id,
          rule.routing_rule_id
        )

      edit = %{
        kind: "spacecraft_profile",
        action: :update,
        entity_id: c.profile_id,
        changes: [%{path: "frame_parameters.frame_size", value: 1024}],
        options: %{rollout: "all"}
      }

      assert {:ok, %{verdict: :hold, checks: checks}} =
               Configuration.preview(c.scope, c.mission.mission_id, {:ops, [edit]})

      assert %{
               items: [
                 %{reason: :framing_unverified, cause: :no_inbound_route, spacecraft_count: 1}
               ]
             } =
               Enum.find(checks, &(&1.key == "compatibility"))
    end

    test "a frame_size override on one spacecraft holds too", c do
      override = %{
        kind: "spacecraft_override",
        action: :update,
        entity_id: c.craft.spacecraft_id,
        changes: [
          %{path: "frame_parameters/frame_size", value: %{"value" => 1024, "reason" => "test"}}
        ]
      }

      assert {:ok, %{verdict: :hold, checks: checks}} =
               Configuration.preview(c.scope, c.mission.mission_id, {:ops, [override]})

      assert %{items: [%{profile_value: %{value: 1024}, transport_value: %{value: 1115}} | _]} =
               Enum.find(checks, &(&1.key == "compatibility"))
    end
  end

  test "profile framing generations are on by default, and a mission can turn them off",
       c do
    assert ConfigurationSettings.profile_framing_generations?(c.org, c.mission.mission_id)

    {:ok, _} =
      ConfigurationSettings.put_profile_framing_generations(c.org, c.mission.mission_id, false, %{
        id: "test",
        name: "Test"
      })

    refute ConfigurationSettings.profile_framing_generations?(c.org, c.mission.mission_id)
  end

  test "with the flag off the same change set produces no activation", c do
    {:ok, _} =
      ConfigurationSettings.put_profile_framing_generations(c.org, c.mission.mission_id, false, %{
        id: "test",
        name: "Test"
      })

    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert {:error, {:checks_failed, _}} = apply_framing_profile(c, 1279)

    {:ok, after_attempt} =
      Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert after_attempt.generation == before.generation
  end

  defp feeding_transport(station) do
    %{
      "display_name" => "Svalbard TCP",
      "ground_station_id" => station,
      "configuration" => %{
        "mode" => "listen",
        "direction_capability" => "inbound",
        "host" => "0.0.0.0",
        "port" => "5000",
        "framing_mode" => "raw",
        "tls_enabled" => "false",
        "ingress_metadata" => %{"frame_size" => 1115, "ocf_length" => 0}
      }
    }
  end

  defp route_craft(c, transport_id) do
    {:ok, transport} =
      TransportStore.fetch_transport(c.org, c.mission.mission_id, transport_id)

    {:ok, _} =
      RoutingRuleStore.create_routing_rule(
        c.org,
        RoutingRule.new(%{
          mission_id: c.mission.mission_id,
          spacecraft_id: c.craft.spacecraft_id,
          display_name: "Svalbard downlink",
          purpose_label: "TT&C",
          direction: :inbound,
          transport_id: transport_id,
          transport_version: transport.version
        })
      )
  end

  defp create_profile(profile_id, frame_size) do
    %{
      kind: "spacecraft_profile",
      action: :create,
      entity_id: profile_id,
      document: %{
        "display_name" => "Framed",
        "downlink_protocol" => "tm",
        "uplink_protocol" => "tc",
        "frame_parameters" => %{"frame_size" => frame_size, "ocf_length" => 0}
      }
    }
  end

  defp pin(spacecraft_id, profile_id) do
    %{
      kind: "spacecraft",
      action: :update,
      entity_id: spacecraft_id,
      changes: [
        %{path: "spacecraft_type_id", value: profile_id},
        %{path: "spacecraft_type_version", value: 1}
      ]
    }
  end

  defp apply_ops!(c, ops) do
    {:ok, staged} = Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Setup"}, ops)
    {:ok, %{state: :applied}} = submit(c, staged)
  end

  # Creates a profile with the given frame size and pins the craft to it.
  defp apply_framing_profile(c, frame_size) do
    profile_id = "profile-framing-#{System.unique_integer([:positive])}"

    {:ok, staged} =
      Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Framing"}, [
        %{
          kind: "spacecraft_profile",
          action: :create,
          entity_id: profile_id,
          document: %{
            "display_name" => "Framed",
            "downlink_protocol" => "tm",
            "uplink_protocol" => "tc",
            "frame_parameters" => %{"frame_size" => frame_size, "ocf_length" => 4}
          }
        }
      ])

    {:ok, %{state: :applied}} = submit(c, staged)

    {:ok, staged} =
      Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Pin"}, [
        %{
          kind: "spacecraft",
          action: :update,
          entity_id: c.craft.spacecraft_id,
          changes: [
            %{path: "spacecraft_type_id", value: profile_id},
            %{path: "spacecraft_type_version", value: 1}
          ]
        }
      ])

    submit(c, staged)
  end

  defp submit(c, staged) do
    Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
      reason: "Profile framing test change",
      expected_version: staged.version,
      acknowledged_holds: true
    })
  end

  defp configure_legacy(scope, mission, craft, revision) do
    current = Drafts.snapshot(mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => revision.catalog_revision_id,
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
