defmodule Cadence.Repo.Migrations.CreateSemanticLivePolicies do
  use Ecto.Migration

  # #451 T3b: the monitoring policies the mission's newest applied generation keeps. Written by the
  # retirement that generation runs (`SemanticObservations.retire_rules/6`), and read when a batch
  # is persisted: a batch evaluated under an OLDER generation must not bring back the state of a
  # policy a newer one retired. One row per mission; the generation only moves forward.
  def change do
    create table(:semantic_live_policies, primary_key: false) do
      add(:organization_id, :string, primary_key: true, collation: "C")
      add(:mission_id, :string, primary_key: true, collation: "C")
      add(:generation, :integer, null: false)
      add(:policy_ids, {:array, :text}, null: false, default: [])
      timestamps(type: :utc_datetime_usec)
    end

    create(
      constraint(:semantic_live_policies, :semantic_live_policies_positive,
        check: "generation > 0"
      )
    )
  end
end
