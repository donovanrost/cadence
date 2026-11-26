defmodule Cadence.MissionModels.CompositionApprovalTest do
  @moduledoc """
  #542 (design E1, `mission-composition-design.md` §4): the model gate approves compositions.
  Separation covers every imported layer's importers and the composer; the approval evidence
  names the combination (each layer's id, mount and digest); a revision no composition names is
  refused as before.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.Actor
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Comparison, Compositions, RevisionRow}
  alias Cadence.Persistence.JsonDocument

  @payload_yaml """
  packets:
    - name: PAYLOAD
      apid: 77
      items:
        - name: power
          data_type: uint
          bit_offset: 0
          bit_size: 8
  commands: []
  """

  setup do
    org = "org-composition-approval-#{System.unique_integer([:positive])}"
    mid = "mission-composition-approval-#{System.unique_integer([:positive])}"
    %{organization: organization} = persist_mission_scope(org, mid)
    c = %{org: org, mid: mid, organization: organization}

    bus = import!(c, "importer-a", "Bus", nil)
    payload = import!(c, "importer-b", "Payload", @payload_yaml)
    Map.merge(c, %{bus_layer: layer!(c, bus), payload_layer: layer!(c, payload)})
  end

  test "a composition's approval separates every layer's importer and the composer", c do
    layers = [{c.bus_layer, "/"}, {c.payload_layer, "/payload"}]
    {:ok, composer} = Actor.from_scope(scope(c, "composer-c"))
    {:ok, composition} = Compositions.insert_or_get(c.org, c.mid, layers, composer)

    {:ok, revision} =
      Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)

    report = compare!(c, revision)

    for refused <- ["importer-a", "importer-b", "composer-c"] do
      assert {:error, :mission_model_self_approval_forbidden} =
               approve(c, refused, revision, report),
             refused
    end

    assert {:ok, _approved} = approve(c, "admin-d", revision, report)

    assert %{"composition_id" => composition_id, "imported_layers" => recorded} =
             evidence!(revision)["composition"]

    assert composition_id == composition.composition_id

    assert Enum.map(recorded, &{&1["layer_id"], &1["mount"], &1["content_sha256"]}) ==
             Enum.map(composition.imported_layers, &{&1.layer_id, &1.mount, &1.content_sha256})

    assert Enum.all?(recorded, &is_binary(&1["content_sha256"]))
  end

  test "a system composer without run_by counts no one; the layers' importers still do", c do
    layers = [{c.bus_layer, "/"}, {c.payload_layer, "/p2"}]
    system = %{"actor_kind" => "system", "system_id" => "cadence", "name" => "Cadence"}
    {:ok, composition} = Compositions.insert_or_get(c.org, c.mid, layers, system)

    {:ok, revision} =
      Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)

    report = compare!(c, revision)

    for refused <- ["importer-a", "importer-b"] do
      assert {:error, :mission_model_self_approval_forbidden} =
               approve(c, refused, revision, report)
    end

    assert {:ok, _approved} = approve(c, "admin-c", revision, report)
  end

  test "a one-layer composition (an import's own) approves exactly as before", c do
    {:ok, composition} = Compositions.fetch(c.org, c.mid, one_layer_id(c))

    {:ok, revision} =
      Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)

    report = compare!(c, revision)

    assert {:error, :mission_model_self_approval_forbidden} =
             approve(c, "importer-a", revision, report)

    assert {:ok, _approved} = approve(c, "admin-c", revision, report)
    assert evidence!(revision)["composition"]["composition_id"] == composition.composition_id
  end

  test "a revision no composition names is refused with the code it always had", c do
    assert {:error, :mission_model_revision_not_in_catalog} =
             MissionModels.require_composition(c.org, c.mid, "mission_model_revision:unnamed")
  end

  defp import!(c, user_id, label, yaml) do
    {:ok, actor} = Actor.from_scope(scope(c, user_id))
    opts = [approve: false, requested_by: actor, revision_label: label]
    opts = if yaml, do: Keyword.put(opts, :yaml, yaml), else: opts
    Fixtures.persist_imported_revision!(c.org, c.mid, opts)
  end

  defp layer!(c, catalog_revision) do
    {:ok, composition} =
      Compositions.for_revision(c.org, c.mid, catalog_revision.mission_model_revision_id)

    [%{layer_id: layer_id, mount: "/"}] = composition.imported_layers
    layer_id
  end

  # What the approval recorded (`approved_by`, a wrapped document).
  defp evidence!(revision_id),
    do:
      RevisionRow
      |> Repo.get!(revision_id)
      |> Map.fetch!(:approved_by)
      |> JsonDocument.unwrap_value()

  defp one_layer_id(c), do: Compositions.id(c.org, c.mid, [{c.bus_layer, "/"}])

  defp compare!(c, revision) do
    {:ok, report} = Comparison.run(c.org, c.mid, revision, "composition-binding", 1)
    report
  end

  defp approve(c, user_id, revision, report),
    do:
      MissionModels.approve_revision(
        scope(c, user_id),
        c.mid,
        revision,
        report["comparison_report_id"]
      )

  defp scope(c, user_id) do
    Scope.new(%{
      user:
        User.new(%{user_id: user_id, email: "#{user_id}@example.test", display_name: user_id}),
      organization_id: c.organization.organization_id,
      organization: c.organization,
      organization_membership:
        OrganizationMembership.new(%{
          user_id: user_id,
          organization_id: c.organization.organization_id,
          role: :organization_admin
        })
    })
  end
end
