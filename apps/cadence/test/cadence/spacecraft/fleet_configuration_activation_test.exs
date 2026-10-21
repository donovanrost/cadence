defmodule Cadence.Activations.FleetConfigurationTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Active, Drafts, Review}
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.SpacecraftModelBindings
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Reads.Spacecraft.Configuration, as: ConfigurationRead

  setup do
    org = "org-fleet-activation"
    mid = "mission-fleet-activation"
    {first, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    %{org: org, mission: mission, scope: scope, first: first, revision: revision}
  end

  @tag timeout: 180_000
  test "500 spacecraft activate together and retain usable command and telemetry bases", c do
    fleet = [
      c.first
      | Enum.map(2..500, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    tokens = Map.new(fleet, fn craft -> {craft.spacecraft_id, save(c, craft)} end)
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    assert byte_size(Jason.encode!(request.metadata)) > 65_536
    assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    assert {:ok, execution} = ControlActivations.execute(approved)
    assert execution.status == :succeeded
    assert {:ok, active} = Active.load(c.mission)
    assert map_size(active.entries) == 500

    for craft <- fleet do
      entry = active.entries[craft.spacecraft_id]
      assert entry["commanding_enabled"]
      assert entry["document"]["telemetry_enabled"]

      assert {:ok, config} =
               TelemetryDecom.fetch_config(c.org, c.mission.mission_id, craft.spacecraft_id)

      assert config.applied_binding_set_version == active.binding_set.version
      assert config.applied_at

      assert Activations.latest_spacecraft_request(
               c.org,
               c.mission.mission_id,
               craft.spacecraft_id
             ).activation_request_id == request.activation_request_id
    end

    last = List.last(fleet)
    source = hd(active.entries[last.spacecraft_id]["source_endpoint_ids"])

    assert {:ok, basis} =
             Cadence.Activations.with_locked_command_basis(
               c.org,
               c.mission.mission_id,
               fn activation ->
                 SpacecraftModelBindings.command_basis(activation, source)
               end
             )

    assert basis.mission_model_revision_id == c.revision.mission_model_revision_id
    assert {:ok, spec} = Cadence.Runtime.Missions.applied_spec(c.mission.mission_id)
    assert map_size(spec.source_runtime_bases) >= 500

    assert {:ok, %{review: %{state: "active"}}} =
             ConfigurationRead.load(c.scope, c.mission, last.spacecraft_id, "changes")
  end

  test "fleet review retains independent approval and rejects self approval", c do
    policy = ActivationPolicy.load(c.org, c.mission.mission_id)

    {:ok, _} =
      ActivationPolicy.save(c.scope, c.mission.mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })

    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Second")
    tokens = Map.new([c.first, second], &{&1.spacecraft_id, save(c, &1)})
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    assert request.state == :approval_pending

    assert {:error, :activation_request_not_approved} =
             Activations.fetch_approved(request.activation_request_id)

    assert {:error, :activation_self_approval_forbidden} =
             Activations.approve(c.scope, request.activation_request_id, "Reviewed fleet")

    assert {:ok, execution} =
             ControlActivations.approve_and_execute(
               Fixtures.user_scope(c.org, "reviewer"),
               request.activation_request_id,
               "Reviewed both spacecraft"
             )

    assert execution.status == :succeeded
  end

  test "a stale spacecraft rejects the whole fleet activation", c do
    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Second")
    tokens = Map.new([c.first, second], &{&1.spacecraft_id, save(c, &1)})
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    save(c, second, false)
    assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    assert {:error, :spacecraft_configuration_changed} = ControlActivations.execute(approved)

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    {:ok, first} =
      Cadence.SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, c.first.spacecraft_id)

    refute first.metadata["spacecraft_configuration_revision_id"]
  end

  test "an empty or oversized review is rejected", c do
    assert {:error, :spacecraft_configuration_review_unavailable} =
             Review.request_many(c.scope, c.mission.mission_id, %{})

    tokens = Map.new(1..501, &{"spacecraft-#{&1}", "token"})

    assert {:error, :spacecraft_configuration_review_unavailable} =
             Review.request_many(c.scope, c.mission.mission_id, tokens)
  end

  defp save(c, craft, commanding \\ true) do
    current = Drafts.snapshot(c.mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => commanding,
        "handled_apids" => [42]
      })

    assert {:ok, _} =
             Drafts.save(
               c.scope,
               c.mission.mission_id,
               craft.spacecraft_id,
               current.token,
               document
             )

    Drafts.snapshot(c.mission, craft).token
  end
end
