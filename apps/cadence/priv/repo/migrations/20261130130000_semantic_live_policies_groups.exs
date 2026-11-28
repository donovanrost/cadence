defmodule Cadence.Repo.Migrations.SemanticLivePoliciesGroups do
  use Ecto.Migration

  # #451, after M: a mission runs several model revisions at once (one per composition), so what a
  # generation keeps is a set of policies PER GROUP OF SPACECRAFT, not one set. `groups` is
  # `[{"policies": [...], "spacecraft": [...] | "all"}]`; `policy_ids` stays the union.
  def change do
    alter table(:semantic_live_policies) do
      add(:groups, :map, null: false, default: fragment("'[]'::jsonb"))
    end
  end
end
