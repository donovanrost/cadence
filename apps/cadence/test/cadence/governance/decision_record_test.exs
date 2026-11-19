defmodule Cadence.Governance.DecisionRecordTest do
  @moduledoc "The four-eyes decision record contract (P3 step 1)."
  use Cadence.UnitCase, async: true

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias Cadence.Governance.DecisionRecord

  @subject %{kind: "change_set", id: "cs-1", version: 3, digest: "sha-abc"}

  test "the actor and admin mode come from the scope" do
    assert {:ok, record} =
             DecisionRecord.new(scope("u-1"), %{decision: :approved, subject: @subject})

    assert record.actor == %{"kind" => "user", "id" => "u-1"}
    assert record.admin_mode == false
    assert record.separated_from == []
    assert %DateTime{} = record.decided_at

    assert {:ok, %{admin_mode: true}} =
             DecisionRecord.new(scope("u-2", admin_mode?: true), %{
               decision: :approved,
               subject: @subject
             })
  end

  test "an actor or admin mode passed in is refused" do
    for key <- [:actor, :admin_mode] do
      assert {:error, {:decision_record_field_from_scope, ^key}} =
               DecisionRecord.new(
                 scope("u-1"),
                 Map.put(%{decision: :approved, subject: @subject}, key, "x")
               )
    end
  end

  test "reject, send back and withdraw need a reason; blank counts as none" do
    for decision <- [:rejected, :sent_back, :withdrawn] do
      assert {:error, :decision_record_reason_required} =
               DecisionRecord.new(scope("u-1"), %{
                 decision: decision,
                 subject: @subject,
                 reason: "  "
               })

      assert {:ok, %{reason: "Wrong window"}} =
               DecisionRecord.new(scope("u-1"), %{
                 decision: decision,
                 subject: @subject,
                 reason: " Wrong window "
               })
    end

    assert {:ok, %{reason: nil}} =
             DecisionRecord.new(scope("u-1"), %{
               decision: :approved,
               subject: @subject,
               reason: ""
             })
  end

  test "approved and not_required name the digest the apply compares" do
    for decision <- [:approved, :not_required] do
      assert {:error, :decision_record_digest_required} =
               DecisionRecord.new(scope("u-1"), %{
                 decision: decision,
                 subject: Map.delete(@subject, :digest)
               })
    end

    assert {:ok, %{subject: %{digest: nil}}} =
             DecisionRecord.new(scope("u-1"), %{
               decision: :rejected,
               reason: "No",
               subject: Map.delete(@subject, :digest)
             })
  end

  test "an unknown decision, a missing subject or a bad separated_from is refused" do
    assert {:error, :decision_record_decision_invalid} =
             DecisionRecord.new(scope("u-1"), %{decision: :maybe, subject: @subject})

    assert {:error, :decision_record_subject_required} =
             DecisionRecord.new(scope("u-1"), %{decision: :approved, subject: %{kind: "x"}})

    assert {:error, :decision_record_separated_from_invalid} =
             DecisionRecord.new(scope("u-1"), %{
               decision: :approved,
               subject: @subject,
               separated_from: ["", nil]
             })

    assert {:ok, %{separated_from: ["author", "submitter"]}} =
             DecisionRecord.new(scope("u-1"), %{
               decision: :approved,
               subject: @subject,
               separated_from: ["author", "submitter", "author"]
             })
  end

  defp scope(user_id, opts \\ []) do
    Scope.new(%{
      user:
        User.new(%{
          user_id: user_id,
          email: "#{user_id}@example.test",
          display_name: user_id,
          capabilities: if(opts[:admin_mode?], do: [:platform_admin], else: [])
        }),
      organization_id: "org-decision-record",
      admin_mode?: Keyword.get(opts, :admin_mode?, false)
    })
  end
end
