defmodule Cadence.Repo.Migrations.AddPassPredictionSearchBasis do
  use Ecto.Migration

  # #892: what each recompute run actually searched, so an opportunity is flagged
  # no_predicted_pass only with per-pair evidence: per spacecraft the element set and window,
  # per station the geometry fingerprint and from when, and the prune bound.
  def change do
    alter table(:pass_prediction_states) do
      add(:search_basis, :map, null: false, default: %{})
    end
  end
end
