defmodule Cadence.MissionModels.AuthoredHeadTest do
  @moduledoc """
  ADR-020 P3 slice M1 (#451): the mission's authored layer is versioned; a composition compiles
  at the authored head; and a revision at a head is approved only as its base plus a recorded
  head, never on its own.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Configuration.{ChangeSetRow, ChangeSetStore, Ledger}
  alias Cadence.Control.AuthoredVersions
  alias Cadence.Control.ModelApprovalGate
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{AuthoredHead, Compositions, EffectiveRevisionRow, RevisionRow}

  setup do
    org = "org-authored-#{System.unique_integer([:positive])}"
    mid = "mission-authored-#{System.unique_integer([:positive])}"
    {_craft, catalog, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    base = catalog.mission_model_revision_id
    {:ok, composition} = Compositions.for_revision(org, mid, base)
    # Revision 1, the baseline: what these sets were applied as.
    Ledger.ensure_head(org, mid)
    %{org: org, mid: mid, base: base, composition: composition.composition_id}
  end

  defp authored_layer!(c, marker) do
    {:ok, layer} =
      MissionModels.persist_layer(
        Layer.new(%{
          organization_id: c.org,
          mission_id: c.mid,
          layer_kind: :authored,
          name: "mission monitoring",
          declarations: [%{kind: :parameter, qualified_name: "/authored/" <> marker}]
        })
      )

    layer
  end

  # An applied monitoring set, as revision 1 unless told otherwise.
  defp change_set!(c, attrs \\ []) do
    {:ok, set} =
      Repo.transaction(fn ->
        ChangeSetStore.lock_or_open(
          c.org,
          c.mid,
          1,
          %{"kind" => "user", "id" => "u"},
          "monitoring"
        )
      end)

    set
    |> Ecto.Changeset.change(
      Keyword.merge(
        [
          state: "applied",
          applied_revision_number: 1,
          policy_document: %{"approval_required" => true}
        ],
        attrs
      )
    )
    |> Repo.update!()
  end

  defp record!(c, layer, revision_number) do
    set = change_set!(c, applied_revision_number: revision_number)

    {:ok, version} =
      AuthoredVersions.record(c.org, c.mid, layer.layer_id, set.change_set_id, revision_number)

    version
  end

  test "versions are a sequence; the newest is the head", c do
    assert AuthoredHead.head(c.org, c.mid) == nil

    first = authored_layer!(c, "one")
    assert %{version: 1} = record!(c, first, 1)

    second = authored_layer!(c, "two")
    assert %{version: 2, layer_id: layer_id} = record!(c, second, 1)
    assert AuthoredHead.head(c.org, c.mid).layer_id == layer_id

    assert AuthoredHead.recorded(c.org, c.mid, [first.layer_id, "layer:unknown"]) ==
             MapSet.new([first.layer_id])
  end

  describe "recording a version is the approval, so it is held to the stores" do
    setup c do
      Map.put(c, :layer, authored_layer!(c, "held"))
    end

    defp refused(c, set, attrs \\ []) do
      AuthoredVersions.record(
        c.org,
        c.mid,
        Keyword.get(attrs, :layer_id, c.layer.layer_id),
        set.change_set_id,
        Keyword.get(attrs, :revision_number, 1)
      )
    end

    test "a reviewed set says so; a direct one says direct", c do
      reviewed = change_set!(c)
      assert {:ok, %{approval: "reviewed"}} = refused(c, reviewed)

      direct = change_set!(c, policy_document: %{"approval_required" => false})

      assert {:ok, %{approval: "direct"}} =
               refused(c, direct, layer_id: authored_layer!(c, "direct").layer_id)
    end

    test "a set that isn't this mission's applied monitoring set, as this revision", c do
      assert {:error, :authored_version_change_set_mismatch} =
               refused(c, change_set!(c, state: "in_review"))

      Repo.delete_all(ChangeSetRow)

      assert {:error, :authored_version_change_set_mismatch} =
               refused(c, change_set!(c, lane: "configuration"))

      Repo.delete_all(ChangeSetRow)

      assert {:error, :authored_version_change_set_mismatch} =
               refused(c, change_set!(c), revision_number: 2)
    end

    test "a ledger revision that doesn't exist", c do
      set = change_set!(c, applied_revision_number: 999)

      assert {:error, :authored_version_revision_unknown} =
               refused(c, set, revision_number: 999)
    end

    test "a layer that isn't this mission's authored layer", c do
      {:ok, imported} =
        MissionModels.persist_layer(
          Layer.new(%{
            organization_id: c.org,
            mission_id: c.mid,
            name: "imported",
            declarations: [%{kind: :parameter, qualified_name: "/imported/x"}]
          })
        )

      assert {:error, :authored_version_layer_mismatch} =
               refused(c, change_set!(c), layer_id: imported.layer_id)

      Repo.delete_all(ChangeSetRow)

      assert {:error, :authored_version_layer_mismatch} =
               refused(c, change_set!(c), layer_id: "mission_model_layer:elsewhere")
    end

    test "one set records one version", c do
      set = change_set!(c)
      assert {:ok, _} = refused(c, set)

      assert {:error, :authored_version_already_recorded} =
               refused(c, set, layer_id: authored_layer!(c, "again").layer_id)
    end
  end

  test "approval_bases maps a head revision to its base and anything else to itself", c do
    layer = authored_layer!(c, "bases")
    record!(c, layer, 1)
    {:ok, head} = Compositions.effective_revision(c.org, c.mid, c.composition, layer.layer_id)

    assert MissionModels.approval_bases(c.org, c.mid, [head, c.base]) == %{
             head => c.base,
             c.base => c.base
           }
  end

  test "a layer that isn't a recorded version never compiles as a head", c do
    layer = authored_layer!(c, "unrecorded")

    assert {:error, :authored_head_not_recorded} =
             Compositions.effective_revision(c.org, c.mid, c.composition, layer.layer_id)
  end

  test "a composition compiles at the head once, with the authored layer last", c do
    layer = authored_layer!(c, "head")
    record!(c, layer, 1)

    assert {:ok, revision_id} =
             Compositions.effective_revision(c.org, c.mid, c.composition, layer.layer_id)

    refute revision_id == c.base

    assert {:ok, ^revision_id} =
             Compositions.effective_revision(c.org, c.mid, c.composition, layer.layer_id)

    assert %EffectiveRevisionRow{authored_head: head} =
             Repo.get_by!(EffectiveRevisionRow, revision_id: revision_id)

    assert head == layer.layer_id
    {:ok, revision} = MissionModels.fetch_revision(c.org, c.mid, revision_id)
    assert List.last(revision.layer_ids) == layer.layer_id
  end

  describe "a revision at a head is its base plus the head" do
    setup c do
      layer = authored_layer!(c, "approval")
      record!(c, layer, 1)

      {:ok, head_revision} =
        Compositions.effective_revision(c.org, c.mid, c.composition, layer.layer_id)

      Map.put(c, :head_revision, head_revision)
    end

    test "unapproved while the base isn't approved, whatever its own row says", c do
      # The fixture's import comes approved; put its base back to a candidate.
      base_status!(c, "candidate")
      assert %{} = statuses = MissionModels.effective_statuses(c.org, c.mid, [c.head_revision])
      assert statuses[c.head_revision] == :candidate
      assert ModelApprovalGate.unapproved(c.org, c.mid, [c.head_revision]) == [c.head_revision]
    end

    test "approved once the base is, with nothing written on the head revision", c do
      MissionModelApproval.approve!(c.org, c.mid, c.base)

      assert MissionModels.effective_statuses(c.org, c.mid, [c.head_revision, c.base]) == %{
               c.head_revision => :approved,
               c.base => :approved
             }

      assert ModelApprovalGate.unapproved(c.org, c.mid, [c.head_revision]) == []
      # Derived, never stored: the head revision's own row is untouched.
      assert Repo.get_by!(RevisionRow, revision_id: c.head_revision).status != "approved"
    end

    test "withdrawn when the base's approval is withdrawn", c do
      MissionModelApproval.approve!(c.org, c.mid, c.base)

      base_status!(c, "withdrawn")

      assert MissionModels.effective_statuses(c.org, c.mid, [c.head_revision]) == %{
               c.head_revision => :withdrawn
             }
    end
  end

  test "the derived read costs the same for one head revision or several", c do
    MissionModelApproval.approve!(c.org, c.mid, c.base)

    revisions =
      for marker <- ~w(a b c) do
        layer = authored_layer!(c, marker)
        record!(c, layer, 1)
        {:ok, id} = Compositions.effective_revision(c.org, c.mid, c.composition, layer.layer_id)
        id
      end

    {_one, one} =
      count_queries(fn ->
        MissionModels.effective_statuses(c.org, c.mid, Enum.take(revisions, 1))
      end)

    {all, three} =
      count_queries(fn -> MissionModels.effective_statuses(c.org, c.mid, revisions) end)

    assert Enum.all?(revisions, &(all[&1] == :approved))
    assert one > 0
    assert three == one
  end

  defp base_status!(c, status) do
    RevisionRow
    |> Repo.get_by!(revision_id: c.base)
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    handler = fn _event, _measurements, _metadata, _config -> send(parent, {ref, :query}) end
    :telemetry.attach(inspect(ref), [:cadence, :repo, :query], handler, nil)

    try do
      result = fun.()
      {result, drain(ref, 0)}
    after
      :telemetry.detach(inspect(ref))
    end
  end

  defp drain(ref, n) do
    receive do
      {^ref, :query} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end
end
