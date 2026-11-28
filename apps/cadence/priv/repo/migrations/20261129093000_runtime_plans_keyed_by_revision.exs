defmodule Cadence.Repo.Migrations.RuntimePlansKeyedByRevision do
  use Ecto.Migration

  # #443 (mission-model overhaul phase 1b): a plan's id now names its content, not its revision, so
  # two revisions that leave a target's plan alone store the same plan_id. A row is one revision's
  # plan for one target; plan_id is a plain index (rows with the same id hold the same content).
  # No backfill: ids stored before this keep the ids they were made with, so dev and stack
  # databases are reset rather than carrying a mix.
  def up do
    execute(
      "ALTER TABLE mission_model_runtime_plans DROP CONSTRAINT mission_model_runtime_plans_pkey"
    )

    execute(
      ~s|ALTER TABLE mission_model_runtime_plans ALTER COLUMN plan_id TYPE varchar(255) COLLATE "C"|
    )

    # The unique (revision_id, target) index becomes the key; it keeps its columns, takes the
    # constraint's name.
    execute("""
    ALTER TABLE mission_model_runtime_plans
      ADD CONSTRAINT mission_model_runtime_plans_pkey
      PRIMARY KEY USING INDEX mission_model_runtime_plans_revision_id_target_index
    """)

    create(index(:mission_model_runtime_plans, [:plan_id]))
  end

  def down do
    drop(index(:mission_model_runtime_plans, [:plan_id]))

    execute(
      "ALTER TABLE mission_model_runtime_plans DROP CONSTRAINT mission_model_runtime_plans_pkey"
    )

    create(unique_index(:mission_model_runtime_plans, [:revision_id, :target]))

    execute(
      "ALTER TABLE mission_model_runtime_plans ADD CONSTRAINT mission_model_runtime_plans_pkey PRIMARY KEY (plan_id)"
    )
  end
end
