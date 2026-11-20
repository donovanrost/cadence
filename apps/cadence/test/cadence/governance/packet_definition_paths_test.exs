defmodule Cadence.Governance.PacketDefinitionPathsTest do
  @moduledoc """
  #534 (domain's note, amendments 1-2; api-ops' condition 2; lead's round-trip condition for 4a):
  every product path that makes a binding set names a packet definition version resolved by
  content, and afterwards EVERY activation's binding set still re-reads to the hash it recorded.

  The bug: a later catalog that redefines a container (same packet_definition_id, version 1, other
  fields) merged its fields into the stored definition, so earlier activations re-read to other
  content. Here catalog A's HEALTH has `mode`; B's and C's HEALTH add a field.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.{Configuration, ConfigurationRollback}
  alias Cadence.Governance
  alias Cadence.Governance.{GovernedPacketDefinitionRow, PacketDefinitionFieldRow}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Runtime.MissionRuntimeSpec

  setup do
    org = "org-pd-paths-#{System.unique_integer([:positive])}"
    mid = "mission-pd-paths-#{System.unique_integer([:positive])}"
    {craft, revision, endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    c = %{org: org, mission: mission, scope: scope, craft: craft, endpoint: endpoint}

    # Fresh activation on catalog A (HEALTH: mode).
    configure!(c, [{craft, revision.catalog_revision_id}])
    Map.put(c, :a, revision.catalog_revision_id)
  end

  test "a fresh activation names version 1 and re-reads to its recorded hash", c do
    assert health_versions(c) == [1]
    assert stored_fields(c) == %{1 => ["mode"]}
    assert_every_activation_rereads(c)
  end

  test "a catalog move to a redefined container names a new version; earlier activations re-read",
       c do
    b = catalog!(c, "B", ["mode", "aux"])
    profile = profile!(c, c.a)
    apply!(c, [update("spacecraft_profile", profile, "catalog_revision_id", b)])

    # The bug itself first: before #534 the earlier activations re-read to merged fields.
    assert_every_activation_rereads(c)
    assert health_versions(c) == [2]
    assert stored_fields(c) == %{1 => ["mode"], 2 => ["aux", "mode"]}
  end

  test "a configuration change on the same catalog reuses the version", c do
    profile = profile!(c, c.a)
    apply!(c, [update("spacecraft_profile", profile, "frame_parameters.frame_size", 1024)])

    assert health_versions(c) == [1]
    assert stored_fields(c) == %{1 => ["mode"]}
    assert_every_activation_rereads(c)
  end

  test "rolling a catalog move back names version 1 again, hydrating catalog A exactly", c do
    b = catalog!(c, "B", ["mode", "aux"])
    profile = profile!(c, c.a)

    %{revision: moved} =
      apply!(c, [update("spacecraft_profile", profile, "catalog_revision_id", b)])

    assert health_versions(c) == [2]

    {:ok, rollback} = ConfigurationRollback.stage(c.scope, c.mission.mission_id, moved - 1)
    assert {:ok, %{state: :applied}} = submit(c, rollback)

    assert health_versions(c) == [1]
    assert stored_fields(c) == %{1 => ["mode"], 2 => ["aux", "mode"]}
    assert_every_activation_rereads(c)
  end

  test "one Review generation over two catalogs gives each new content its own version", c do
    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Craft 2")

    Fixtures.persist_source_endpoint!(c.org, c.mission.mission_id, second.spacecraft_id,
      display_name: "TT&C 2"
    )

    b = catalog!(c, "B", ["mode", "aux"])
    d = catalog!(c, "D", ["mode", "flag"])

    configure!(c, [{c.craft, b}, {second, d}])

    assert Enum.sort(health_versions(c)) == [2, 3]
    assert stored_fields(c) == %{1 => ["mode"], 2 => ["aux", "mode"], 3 => ["flag", "mode"]}
    assert_every_activation_rereads(c)
  end

  # Every activation, current and past: its binding set re-read now hashes as it recorded.
  defp assert_every_activation_rereads(c) do
    activations = Cadence.Activations.list_activations(c.org, c.mission.mission_id)
    assert activations != []

    for activation <- activations do
      assert {:ok, set} =
               Governance.fetch_binding_set(
                 c.org,
                 c.mission.mission_id,
                 activation.binding_set_id,
                 activation.binding_set_version
               )

      assert MissionRuntimeSpec.content_sha256(set) == activation.binding_set_content_sha256,
             "activation #{activation.activation_id} re-reads to another set"
    end
  end

  # The HEALTH packet definition versions the active binding set names.
  defp health_versions(c) do
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    {:ok, set} =
      Governance.fetch_binding_set(
        c.org,
        c.mission.mission_id,
        active.binding_set_id,
        active.binding_set_version
      )

    set.capability_instances
    |> Enum.filter(&match?(%{packet_name: "HEALTH"}, &1.runtime_configuration))
    |> Enum.map(& &1.runtime_configuration.version)
    |> Enum.uniq()
  end

  # Stored HEALTH definitions: version => sorted field names.
  defp stored_fields(c) do
    from(row in GovernedPacketDefinitionRow,
      join: field in PacketDefinitionFieldRow,
      on: field.packet_definition_row_id == row.id,
      where: row.mission_id == ^c.mission.mission_id and row.packet_name == "HEALTH",
      select: {row.version, field.name}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {version, names} -> {version, Enum.sort(names)} end)
  end

  defp catalog!(c, label, fields) do
    items =
      fields
      |> Enum.with_index()
      |> Enum.map_join(fn {name, index} ->
        "      - name: #{name}\n        data_type: uint\n        bit_offset: #{index * 8}\n" <>
          "        bit_size: 8\n"
      end)

    yaml = "packets:\n  - name: HEALTH\n    apid: 42\n    items:\n" <> items <> "commands: []\n"

    Fixtures.persist_imported_revision!(c.org, c.mission.mission_id,
      revision_label: label,
      yaml: yaml
    ).catalog_revision_id
  end

  defp profile!(c, catalog) do
    id = "profile-pd-paths-#{System.unique_integer([:positive])}"

    apply!(c, [
      %{
        kind: "spacecraft_profile",
        action: :create,
        entity_id: id,
        document: %{
          "display_name" => "Paths profile",
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

  defp update(kind, id, path, value),
    do: %{kind: kind, action: :update, entity_id: id, changes: [%{path: path, value: value}]}

  defp apply!(c, ops) do
    {:ok, staged} = Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Paths"}, ops)
    {:ok, %{state: :applied} = applied} = submit(c, staged)
    applied
  end

  defp submit(c, staged) do
    Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
      reason: "Packet definition paths test",
      expected_version: staged.version,
      acknowledged_holds: true
    })
  end

  # One Review over every {spacecraft, catalog}: one generation, so cross-catalog resolution runs.
  defp configure!(c, pairs) do
    tokens =
      Map.new(pairs, fn {craft, catalog} ->
        current = Drafts.snapshot(c.mission, craft)

        document =
          Map.merge(SpacecraftConfigurationInput.empty(), %{
            "catalog_revision_id" => catalog,
            "telemetry_enabled" => true,
            "commanding_enabled" => true,
            "handled_apids" => [42],
            "telemetry_source_endpoint_id" => endpoint_of(c, craft)
          })

        :ok =
          Fixtures.change_set_switches!(
            c.org,
            c.mission.mission_id,
            craft.spacecraft_id,
            document
          )

        {:ok, _} =
          Drafts.save(c.scope, c.mission.mission_id, craft.spacecraft_id, current.token, document)

        {craft.spacecraft_id, Drafts.snapshot(c.mission, craft).token}
      end)

    {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end

  defp endpoint_of(c, craft) do
    Cadence.SourceEndpoints.list_source_endpoints(c.org, c.mission.mission_id)
    |> Enum.find(&(&1.spacecraft_id == craft.spacecraft_id))
    |> case do
      nil -> nil
      endpoint -> endpoint.source_endpoint_id
    end
  end
end
