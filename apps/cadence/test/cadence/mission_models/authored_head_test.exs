defmodule Cadence.MissionModels.AuthoredHeadTest do
  @moduledoc """
  ADR-020 P3 slice M1 (#451): the mission's authored layer is versioned; a composition compiles
  at the authored head; and a revision at a head is approved only as its base plus a recorded
  head, never on its own.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Configuration.{ChangeSetRow, ChangeSetStore, Ledger, ReviewRow}
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

  # An open monitoring set, applied directly by its policy unless told otherwise.
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
      Keyword.merge([policy_document: %{"approval_required" => false}], attrs)
    )
    |> Repo.update!()
  end

  # What an apply does, in order: record the version for the next revision, write that ledger
  # revision, mark the set applied as it; then the commit's deferred checks (SET CONSTRAINTS
  # ALL IMMEDIATE stands in for the commit the sandbox never makes).
  defp apply!(c, layer, opts \\ []) do
    set = Keyword.get_lazy(opts, :set, fn -> change_set!(c) end)

    Repo.transaction(fn ->
      head = Ledger.lock_head(c.org, c.mid)
      number = Keyword.get(opts, :revision_number, head.revision_number + 1)

      case AuthoredVersions.record(c.org, c.mid, layer.layer_id, set, number) do
        {:ok, version} -> finish_apply!(head, set, number, opts, version)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp finish_apply!(head, set, number, opts, version) do
    unless Keyword.get(opts, :skip_ledger), do: write_revision!(head, set)

    unless Keyword.get(opts, :never_applied),
      do: mark_applied!(set, Keyword.get(opts, :applied_as, number))

    Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
    # The sandbox keeps one transaction for the whole test: back to the commit-time default.
    Repo.query!("SET CONSTRAINTS ALL DEFERRED")
    version
  end

  defp mark_applied!(set, number) do
    set
    |> Ecto.Changeset.change(state: "applied", applied_revision_number: number)
    |> Repo.update!()
  end

  defp write_revision!(head, set) do
    {:ok, revision} =
      Ledger.record(
        head,
        %{
          kind: "change_set",
          change_set_id: set.change_set_id,
          applied_by: %{"kind" => "user", "id" => "u"},
          submitted_by: %{"kind" => "user", "id" => "u"},
          applied_at: DateTime.utc_now(),
          reason: "monitoring",
          summary: "monitoring"
        },
        []
      )

    revision
  end

  defp record!(c, layer, _revision_number \\ nil) do
    case apply!(c, layer) do
      {:ok, version} -> version
      other -> flunk("apply failed: #{inspect(other)}")
    end
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

  describe "recording a version is checked now, and again at commit" do
    setup c do
      Map.put(c, :layer, authored_layer!(c, "held"))
    end

    test "a direct set records as direct; a reviewed one as reviewed", c do
      assert {:ok, %{approval: "direct", revision_number: 2}} = apply!(c, c.layer)

      reviewed =
        change_set!(c, state: "in_review", policy_document: %{"approval_required" => true})

      Repo.insert!(%ReviewRow{
        review_id: "review:#{System.unique_integer([:positive])}",
        change_set_id: reviewed.change_set_id,
        organization_id: c.org,
        mission_id: c.mid,
        decision: "approved",
        actor: %{"kind" => "user", "id" => "reviewer"},
        decided_at: DateTime.utc_now(),
        subject_version: reviewed.version,
        subject_digest: String.duplicate("a", 64),
        policy_document: %{"approval_required" => true},
        admin_mode: false
      })

      assert {:ok, %{approval: "reviewed"}} =
               apply!(c, authored_layer!(c, "reviewed"), set: reviewed)
    end

    test "refused now: another lane, another mission, already applied, unsettled approval, the wrong revision",
         c do
      mismatch = {:error, :authored_version_change_set_mismatch}

      assert apply!(c, c.layer, set: change_set!(c, lane: "configuration")) == mismatch
      Repo.delete_all(ChangeSetRow)

      # Another mission's set isn't found under this mission's lock.
      assert apply!(c, c.layer, set: %ChangeSetRow{change_set_id: "change_set:elsewhere"}) ==
               mismatch

      assert apply!(c, c.layer, set: change_set!(c, state: "applied", applied_revision_number: 1)) ==
               mismatch

      Repo.delete_all(ChangeSetRow)
      # Needs approval, and nobody approved it.
      assert apply!(c, c.layer,
               set: change_set!(c, policy_document: %{"approval_required" => true})
             ) ==
               mismatch

      Repo.delete_all(ChangeSetRow)
      assert apply!(c, c.layer, revision_number: 7) == mismatch
    end

    test "refused at commit: never marked applied", c do
      assert_commit_refused(:authored_version_not_applied, fn ->
        apply!(c, c.layer, never_applied: true)
      end)
    end

    test "refused at commit: applied as another revision", c do
      assert_commit_refused(:authored_version_not_applied, fn ->
        apply!(c, c.layer, applied_as: 9)
      end)
    end

    test "refused at commit: the ledger revision was never written", c do
      assert_commit_refused(:authored_version_revision_unknown, fn ->
        apply!(c, c.layer, skip_ledger: true)
      end)
    end

    test "checked immediately, the deferred check refuses before the apply finishes", c do
      set = change_set!(c)

      # The immediate check aborts the transaction, so roll it back to its savepoint, then return
      # the sandbox's one transaction to the commit-time default.
      result =
        Repo.transaction(fn ->
          Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
          head = Ledger.lock_head(c.org, c.mid)

          c.org
          |> AuthoredVersions.record(
            c.mid,
            c.layer.layer_id,
            set,
            head.revision_number + 1
          )
          |> Repo.rollback()
        end)

      Repo.query!("SET CONSTRAINTS ALL DEFERRED")
      # Whichever deferred check fires first: the revision isn't written, nor the set applied.
      assert {:error, {:error, code}} = result
      assert code in [:authored_version_revision_unknown, :authored_version_not_applied]
    end

    test "a rolled-back apply leaves no version and no head", c do
      set = change_set!(c)

      Repo.transaction(fn ->
        head = Ledger.lock_head(c.org, c.mid)

        {:ok, _} =
          AuthoredVersions.record(
            c.org,
            c.mid,
            c.layer.layer_id,
            set,
            head.revision_number + 1
          )

        Repo.rollback(:apply_failed)
      end)

      assert AuthoredHead.head(c.org, c.mid) == nil
    end

    test "one set records one version", c do
      set = change_set!(c)
      assert {:ok, _} = apply!(c, c.layer, set: set)

      again =
        ChangeSetRow
        |> Repo.get!(set.change_set_id)
        |> Ecto.Changeset.change(state: "open", applied_revision_number: nil)
        |> Repo.update!()

      assert {:error, :authored_version_already_recorded} =
               apply!(c, authored_layer!(c, "again"), set: again)
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

      assert {:error, :authored_version_layer_mismatch} = apply!(c, imported)
    end
  end

  defp assert_commit_refused(code, fun) do
    error = assert_raise Postgrex.Error, fun
    assert AuthoredVersions.refusal(error) == code
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
