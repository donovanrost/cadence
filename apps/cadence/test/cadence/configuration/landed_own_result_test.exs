defmodule Cadence.Configuration.LandedOwnResultTest do
  @moduledoc """
  #261: when a submit or review loses its database connection mid-transaction, the recovery
  (`Submission.landed/2`) answers 200 only when the re-read set shows THIS request's own result,
  never a state another person (or another tab) reached. Each case lets a real decision land,
  then asks what a request with a given proof would be told.

  The proof is what the request decided before its transaction (api-ops: ids, not clocks): its
  review row's id, its revision's id, or, for a submit to review that writes no row of its own,
  everything the submit records (actor, version, reason, policy).
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Configuration.{Access, ChangeSetStore, Ledger, ReviewRow, Submission}
  alias Cadence.Control.Configuration

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("landed-261")

    %{
      org: org,
      mission: mission,
      alice: member_scope(org, :member, "Alice"),
      bob: member_scope(org, :member, "Bob"),
      carol: member_scope(org, :member, "Carol")
    }
  end

  describe "under 'independent' (a review is needed)" do
    setup do
      on_exit(with_approval_required(true))
      :ok
    end

    test "a submit to review: this request's own record gives 200; anything else 503", c do
      {staged, before} = stage!(c)
      reason = "Reason for this change"
      submit!(c, c.alice, staged, reason)
      {:ok, landed} = ChangeSetStore.fetch(c.mission, staged.change_set_id)
      own = submit_proof(c.alice, before, reason, landed.policy_document)

      assert {:ok, %{state: :in_review}} = Submission.landed(before, own)

      # Another person's submit, a different reason, or a different policy: not this request's.
      assert {:error, :apply_interrupted} =
               Submission.landed(before, %{own | actor: actor(c.bob)})

      assert {:error, :apply_interrupted} =
               Submission.landed(before, %{own | reason: "Another tab's reason"})

      assert {:error, :apply_interrupted} =
               Submission.landed(before, %{own | policy: %{"approval_required" => false}})

      assert {:error, :apply_interrupted} =
               Submission.landed(before, %{own | version: own.version + 1})
    end

    test "an approve: only this request's own review row proves it", c do
      {staged, _before} = stage!(c)
      submit!(c, c.alice, staged, "Reason for this change")
      {:ok, in_review} = ChangeSetStore.fetch(c.mission, staged.change_set_id)

      assert {:ok, %{state: :applied}} = review!(c, c.bob, in_review, :approve)
      bob_review = review_row!(c, staged)

      own = %{actor: actor(c.bob), act: :approve, review_id: bob_review, revision_id: "x"}
      assert {:ok, %{state: :applied}} = Submission.landed(in_review, own)

      # The bug: Carol's approve dropped its connection after Bob's approval landed. Before
      # #261 she was told 200 for an approval that wasn't hers.
      carol = %{own | actor: actor(c.carol), review_id: "config_review-not-written"}
      assert {:error, :apply_interrupted} = Submission.landed(in_review, carol)

      # The right review row but another actor: the row isn't this actor's decision.
      assert {:error, :apply_interrupted} =
               Submission.landed(in_review, %{own | actor: actor(c.carol)})

      # Bob's own actor but another request's (unwritten) review id: not this request either.
      assert {:error, :apply_interrupted} =
               Submission.landed(in_review, %{own | review_id: "config_review-other-tab"})
    end

    test "a send back: only this request's own review row proves it", c do
      {staged, _before} = stage!(c)
      submit!(c, c.alice, staged, "Reason for this change")
      {:ok, in_review} = ChangeSetStore.fetch(c.mission, staged.change_set_id)

      assert {:ok, %{state: :open}} = review!(c, c.bob, in_review, :send_back)
      bob_review = review_row!(c, staged)

      own = %{actor: actor(c.bob), act: :send_back, review_id: bob_review}
      assert {:ok, %{state: :open}} = Submission.landed(in_review, own)

      assert {:error, :apply_interrupted} =
               Submission.landed(in_review, %{
                 own
                 | actor: actor(c.carol),
                   review_id: "config_review-not-written"
               })

      # An approve's proof against a send back that landed: the set isn't applied.
      assert {:error, :apply_interrupted} =
               Submission.landed(in_review, %{own | act: :approve})
    end
  end

  describe "under 'direct' (a submit applies)" do
    setup do
      on_exit(with_approval_required(false))
      :ok
    end

    test "only this request's own revision id proves the apply", c do
      {staged, before} = stage!(c)

      assert {:ok, %{state: :applied, revision: 2}} =
               submit!(c, c.alice, staged, "Apply the Svalbard station")

      {:ok, revision} = Ledger.fetch_revision(c.mission, 2)

      own = %{
        submit_proof(c.alice, before, "Apply the Svalbard station", nil)
        | revision_id: revision.revision_id
      }

      assert {:ok, %{state: :applied, revision: 2}} = Submission.landed(before, own)

      assert {:error, :apply_interrupted} =
               Submission.landed(before, %{own | revision_id: "config_revision-other-request"})
    end

    test "a set that didn't move is apply_interrupted", c do
      {_staged, before} = stage!(c)
      proof = submit_proof(c.alice, before, "A submit that never landed", nil)
      assert {:error, :apply_interrupted} = Submission.landed(before, proof)
    end
  end

  defp stage!(c) do
    {:ok, staged} =
      Configuration.stage(c.alice, c.mission, %{summary: "Add Svalbard"}, [station_op("Svalbard")])

    {:ok, before} = ChangeSetStore.fetch(c.mission, staged.change_set_id)
    {staged, before}
  end

  defp submit!(c, scope, staged, reason),
    do:
      Configuration.submit(scope, c.mission, staged.change_set_id, %{
        reason: reason,
        expected_version: staged.version
      })

  defp review!(c, scope, set, decision),
    do:
      Configuration.review(scope, c.mission, set.change_set_id, decision, %{
        comment: "Reviewed",
        expected_version: set.version
      })

  defp review_row!(c, staged) do
    [%ReviewRow{review_id: id}] =
      Repo.all(
        from(r in ReviewRow,
          where: r.mission_id == ^c.mission and r.change_set_id == ^staged.change_set_id
        )
      )

    id
  end

  defp submit_proof(scope, before, reason, policy),
    do: %{
      actor: actor(scope),
      act: :submit,
      version: before.version + 1,
      reason: reason,
      policy: policy,
      revision_id: "config_revision-not-this"
    }

  defp actor(scope), do: Access.actor(scope)
end
