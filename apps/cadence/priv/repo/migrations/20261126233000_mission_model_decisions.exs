defmodule Cadence.Repo.Migrations.MissionModelDecisions do
  use Ecto.Migration

  # E2 (#546; design §5, CB-15): a withdrawn model approval is a pure decision record, append-only
  # like the other decision tables (DecisionRecord.tables/0). The revision row's status moves to
  # 'withdrawn' beside it, and that status is terminal. Approvals still live on the revision row;
  # #878 moves them here additively.
  def up do
    create table(:mission_model_decisions, primary_key: false) do
      add(:decision_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)

      add(
        :revision_id,
        references(:mission_model_revisions,
          column: :revision_id,
          type: :string,
          on_delete: :restrict
        ),
        null: false
      )

      add(:composition_id, :string)
      add(:decision, :string, null: false)
      add(:actor, :map, null: false)
      add(:reason, :text, null: false)
      add(:subject, :map, null: false)
      add(:policy_document, :map, null: false)
      add(:admin_mode, :boolean, null: false)
      add(:operation_id, :string)
      add(:decided_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:mission_model_decisions, :mission_model_decisions_decision_check,
        check: "decision IN ('withdrawn')"
      )
    )

    create(
      constraint(:mission_model_decisions, :mission_model_decisions_reason_check,
        check: "length(btrim(reason)) > 0"
      )
    )

    create(index(:mission_model_decisions, [:organization_id, :mission_id, :revision_id]))
    create(unique_index(:mission_model_decisions, [:revision_id, :decision]))

    execute("""
    CREATE TRIGGER mission_model_decisions_append_only_rows BEFORE DELETE OR UPDATE
      ON mission_model_decisions FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only()
    """)

    execute("""
    CREATE TRIGGER mission_model_decisions_append_only_truncate BEFORE TRUNCATE
      ON mission_model_decisions FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only()
    """)

    # Withdrawn is terminal in the database, not only in approve's code (commanding, #546): no
    # UPDATE moves a revision's status away from 'withdrawn'. Running that model again takes a new
    # revision through the full approval.
    execute("""
    CREATE FUNCTION cadence_model_revision_withdrawn_terminal() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF OLD.status = 'withdrawn' AND NEW.status IS DISTINCT FROM 'withdrawn' THEN
        RAISE EXCEPTION 'mission model revision % was withdrawn; withdrawn is terminal', OLD.revision_id
          USING ERRCODE = 'check_violation';
      END IF;
      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER mission_model_revisions_withdrawn_terminal BEFORE UPDATE OF status
      ON mission_model_revisions FOR EACH ROW EXECUTE FUNCTION cadence_model_revision_withdrawn_terminal()
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS mission_model_revisions_withdrawn_terminal ON mission_model_revisions"
    )

    execute("DROP FUNCTION IF EXISTS cadence_model_revision_withdrawn_terminal()")
    drop(table(:mission_model_decisions))
  end
end
