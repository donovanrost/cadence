defmodule Cadence.Configuration.CatalogGenerationTest do
  @moduledoc "Catalog-path generations (DECISIONS #36/#65)."
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{CatalogAuthority, Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.{Configuration, ConfigurationRollback}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations

  setup do
    org = "org-catalog-gen-#{System.unique_integer([:positive])}"
    mid = "mission-catalog-gen-#{System.unique_integer([:positive])}"
    {craft, revision, endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    configure(scope, mission, craft, revision.catalog_revision_id)
    rev2 = Fixtures.persist_imported_revision!(org, mid, revision_label: "Rev 2")

    %{
      org: org,
      mission: mission,
      scope: scope,
      craft: craft,
      endpoint: endpoint,
      rev1: revision.catalog_revision_id,
      rev2: rev2.catalog_revision_id
    }
  end

  test "a profile catalog change set moves its pinned spacecraft onto the new catalog in one generation",
       c do
    profile = profile!(c, c.rev1)
    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    {:ok, staged} =
      stage(c, [update("spacecraft_profile", profile, "catalog_revision_id", c.rev2)])

    assert {:ok, %{verdict: :hold, checks: checks}} =
             Configuration.preview(
               c.scope,
               c.mission.mission_id,
               staged.change_set_id
             )

    assert %{items: items, blocking: false} = Enum.find(checks, &(&1.key == "compatibility"))
    assert Enum.any?(items, &(&1.reason == :catalog_change and &1.to == c.rev2))

    assert {:ok, %{state: :applied, generation: generation, revision: revision}} =
             submit(c, staged)

    assert generation > before.generation

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    assert entry["catalog_revision_id"] == c.rev2

    latest = Drafts.latest(c.org, c.mission.mission_id, c.craft.spacecraft_id)
    assert latest.catalog_revision_id == c.rev2
    assert latest.configuration_revision_id == entry["configuration_revision_id"]
    assert CatalogAuthority.mismatches(c.org, c.mission.mission_id) == []

    # Rolling it back goes the same way.
    {:ok, rollback} = ConfigurationRollback.stage(c.scope, c.mission.mission_id, revision - 1)
    assert {:ok, %{state: :applied}} = submit(c, rollback)

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert {:ok, %{"catalog_revision_id" => rev1}} =
             FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)

    assert rev1 == c.rev1
  end

  test "waiting commands are canceled with catalog_changed; a command in flight blocks the apply",
       c do
    profile = profile!(c, c.rev1)
    waiting = request!(c, "validated")
    in_flight = request!(c, "released", verification_state: "pending")

    {:ok, staged} =
      stage(c, [update("spacecraft_profile", profile, "catalog_revision_id", c.rev2)])

    assert {:ok, %{checks: checks}} =
             Configuration.preview(
               c.scope,
               c.mission.mission_id,
               staged.change_set_id
             )

    assert %{items: items, blocking: true} = Enum.find(checks, &(&1.key == "compatibility"))
    reasons = MapSet.new(items, & &1.reason)
    assert :catalog_cancels_commands in reasons and :catalog_command_in_flight in reasons

    assert {:error, {:holds_blocking, _preview}} = submit(c, staged)

    # The command finishes; now the apply goes through and cancels the waiting one.
    Repo.query!(
      "UPDATE command_requests SET verification_state = 'satisfied' WHERE command_request_id = $1",
      [
        in_flight
      ]
    )

    assert {:ok, %{state: :applied}} = submit(c, staged)

    %{rows: [[state, metadata]]} =
      Repo.query!(
        "SELECT lifecycle_state, metadata_document FROM command_requests WHERE command_request_id = $1",
        [waiting]
      )

    assert state == "canceled"
    assert get_in(metadata, ["value", "cancellation", "reason"]) =~ "catalog_changed: "
  end

  test "a profile catalog has one writer: the spacecraft's own configuration can't diverge, and divergence is listed",
       c do
    # The pin moves the craft onto rev2; then its configuration diverges, as data from before
    # #65 can.
    profile!(c, c.rev2)
    latest = Drafts.latest(c.org, c.mission.mission_id, c.craft.spacecraft_id)

    Repo.query!(
      "UPDATE spacecraft_configuration_revisions SET catalog_revision_id = $1 " <>
        "WHERE configuration_revision_id = $2",
      [c.rev1, latest.configuration_revision_id]
    )

    assert [
             %{
               spacecraft_id: id,
               effective_catalog_revision_id: rev2,
               configured_catalog_revision_id: rev1
             }
           ] =
             CatalogAuthority.mismatches(c.org, c.mission.mission_id)

    assert {id, rev2, rev1} == {c.craft.spacecraft_id, c.rev2, c.rev1}

    current = Drafts.snapshot(c.mission, c.craft)

    assert {:error, :spacecraft_catalog_set_by_profile} =
             Drafts.save(
               c.scope,
               c.mission.mission_id,
               c.craft.spacecraft_id,
               current.token,
               Map.put(current.document, "catalog_revision_id", c.rev1)
             )
  end

  ## Helpers

  # A profile with `catalog`, the craft pinned to it.
  defp profile!(c, catalog) do
    id = "profile-catalog-#{System.unique_integer([:positive])}"

    apply!(c, [
      %{
        kind: "spacecraft_profile",
        action: :create,
        entity_id: id,
        document: %{
          "display_name" => "Catalog profile",
          "downlink_protocol" => "tm",
          "uplink_protocol" => "tc",
          "catalog_revision_id" => catalog,
          "frame_parameters" => %{"frame_size" => 1115, "ocf_length" => 4}
        }
      }
    ])

    apply!(c, [
      %{
        kind: "spacecraft",
        action: :update,
        entity_id: c.craft.spacecraft_id,
        changes: [
          %{path: "spacecraft_type_id", value: id},
          %{path: "spacecraft_type_version", value: 1}
        ]
      }
    ])

    id
  end

  defp request!(c, state, opts \\ []) do
    id = "command-request-#{System.unique_integer([:positive])}"

    Repo.query!(
      """
      INSERT INTO command_requests (command_request_id, organization_id, mission_id,
        source_endpoint_ref, mission_model_revision_id, command_id, command_name, lifecycle_state,
        verification_state, requested_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 'model', 'command', 'NOOP', $5, $6, now(), now(), now())
      """,
      [
        id,
        c.org,
        c.mission.mission_id,
        c.endpoint.source_endpoint_id,
        state,
        Keyword.get(opts, :verification_state)
      ]
    )

    id
  end

  defp update(kind, id, path, value),
    do: %{kind: kind, action: :update, entity_id: id, changes: [%{path: path, value: value}]}

  defp stage(c, ops),
    do: Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Catalog"}, ops)

  defp apply!(c, ops) do
    {:ok, staged} = stage(c, ops)
    {:ok, %{state: :applied}} = submit(c, staged)
  end

  defp submit(c, staged) do
    Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
      reason: "Catalog generation test",
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
