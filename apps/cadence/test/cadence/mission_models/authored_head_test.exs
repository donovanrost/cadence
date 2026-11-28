defmodule Cadence.MissionModels.AuthoredHeadTest do
  @moduledoc """
  ADR-020 P3 slice M1 (#451): the mission's authored layer is versioned; a composition compiles
  at the authored head; and a revision at a head is approved only as its base plus a recorded
  head, never on its own.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Configuration.ChangeSetStore
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

  defp change_set!(c) do
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
  end

  defp record!(c, layer, revision_number) do
    {:ok, version} =
      AuthoredHead.record(
        c.org,
        c.mid,
        layer.layer_id,
        change_set!(c).change_set_id,
        revision_number
      )

    version
  end

  test "versions are a sequence; the newest is the head", c do
    assert AuthoredHead.head(c.org, c.mid) == nil

    first = authored_layer!(c, "one")
    assert %{version: 1} = record!(c, first, 2)

    second = authored_layer!(c, "two")
    assert %{version: 2, layer_id: layer_id} = record!(c, second, 3)
    assert AuthoredHead.head(c.org, c.mid).layer_id == layer_id

    assert AuthoredHead.recorded(c.org, c.mid, [first.layer_id, "layer:unknown"]) ==
             MapSet.new([first.layer_id])
  end

  test "a layer that isn't a recorded version never compiles as a head", c do
    layer = authored_layer!(c, "unrecorded")

    assert {:error, :authored_head_not_recorded} =
             Compositions.effective_revision(c.org, c.mid, c.composition, layer.layer_id)
  end

  test "a composition compiles at the head once, with the authored layer last", c do
    layer = authored_layer!(c, "head")
    record!(c, layer, 2)

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
      record!(c, layer, 2)

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
        record!(c, layer, 2)
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
