defmodule Cadence.Configuration.FramingGenerationTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
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

  test "with the flag off the same change set produces no activation", c do
    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert {:error, {:checks_failed, _}} = apply_framing_profile(c, 1279)

    {:ok, after_attempt} =
      Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert after_attempt.generation == before.generation
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
