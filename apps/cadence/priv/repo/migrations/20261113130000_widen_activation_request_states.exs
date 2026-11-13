defmodule Cadence.Repo.Migrations.WidenActivationRequestStates do
  use Ecto.Migration

  # L10: a requester may withdraw a pending request, and a newer request for the same binding set
  # supersedes older pending ones (recording which). Existing rows keep their states.
  def up do
    # Requests are read on every activation; fail fast rather than queue readers (qa).
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:activation_requests) do
      add(:superseded_by, :string, null: true)
      add(:superseded_at, :utc_datetime_usec, null: true)
    end

    drop(constraint(:activation_requests, :activation_requests_state_check))

    create(
      constraint(:activation_requests, :activation_requests_state_check,
        check: "state IN ('approval_pending', 'approved', 'rejected', 'withdrawn', 'superseded')"
      )
    )

    drop(constraint(:activation_decisions, :activation_decisions_decision_check))

    create(
      constraint(:activation_decisions, :activation_decisions_decision_check,
        check: "decision IN ('approved', 'rejected', 'withdrawn')"
      )
    )
  end

  def down do
    execute("SET LOCAL lock_timeout = '5s'")
    drop(constraint(:activation_decisions, :activation_decisions_decision_check))

    create(
      constraint(:activation_decisions, :activation_decisions_decision_check,
        check: "decision IN ('approved', 'rejected')"
      )
    )

    drop(constraint(:activation_requests, :activation_requests_state_check))

    create(
      constraint(:activation_requests, :activation_requests_state_check,
        check: "state IN ('approval_pending', 'approved', 'rejected')"
      )
    )

    alter table(:activation_requests) do
      remove(:superseded_at)
      remove(:superseded_by)
    end
  end
end
