defmodule Cadence.MissionModels.PinBackfill do
  @moduledoc """
  D3's migration of catalog pins to composition pins (#544; design §3), run by migration
  20261120200000 in its own transaction. Every catalog revision's model revision is a one-import
  compile at '/' whose one-layer composition D1 made (#559), so:

  - each profile row (every version) pinning a catalog revision gets that composition's id in
    `composition_id`;
  - each per-craft `catalog_revision_id` override gets a `composition_id` override beside it,
    with the same reason and revision, set by a system actor that counts no one.

  `catalog_revision_id` is left as it is: provenance from now on. The writes are raw SQL, so a
  later schema change can't change what this did; `Compositions.id/3` is pinned by its golden
  (#108). It **raises** rather than leave a pin without a composition: a pinned catalog revision
  whose model revision isn't one imported layer in its own mission, or whose composition doesn't
  exist (qa's read-only pre-check counts these before the landing). Idempotent.
  """

  alias Cadence.MissionModels.Compositions

  @actor %{"actor_kind" => "system", "system_id" => "migration:20261120200000"}

  @doc "Fills the composition pins; returns the counts."
  @spec run(module()) :: %{profiles: non_neg_integer(), overrides: non_neg_integer()}
  def run(repo) do
    now = DateTime.utc_now()

    profiles =
      repo
      |> pinned_profiles()
      |> Enum.reduce(0, fn {org, mission, catalog}, count ->
        composition_id = composition!(repo, org, mission, catalog)
        %{num_rows: n} = pin_profiles(repo, org, mission, catalog, composition_id)
        count + n
      end)

    overrides =
      repo
      |> pinned_overrides()
      |> Enum.reduce(0, fn override, count ->
        composition_id =
          composition!(repo, override.organization_id, override.mission_id, override.catalog)

        %{num_rows: n} = pin_override(repo, override, composition_id, now)
        count + n
      end)

    %{profiles: profiles, overrides: overrides}
  end

  defp pinned_profiles(repo) do
    %{rows: rows} =
      repo.query!("""
      SELECT DISTINCT organization_id, mission_id, catalog_revision_id
      FROM mission_spacecraft_types
      WHERE catalog_revision_id IS NOT NULL AND composition_id IS NULL
      ORDER BY 1, 2, 3
      """)

    Enum.map(rows, &List.to_tuple/1)
  end

  defp pin_profiles(repo, org, mission, catalog, composition_id),
    do:
      repo.query!(
        """
        UPDATE mission_spacecraft_types SET composition_id = $4
        WHERE organization_id = $1 AND mission_id = $2 AND catalog_revision_id = $3
          AND composition_id IS NULL
        """,
        [org, mission, catalog, composition_id]
      )

  defp pinned_overrides(repo) do
    %{rows: rows} =
      repo.query!("""
      SELECT o.organization_id, o.mission_id, o.spacecraft_id, o.value->>'value', o.reason,
             o.set_in_revision
      FROM spacecraft_config_overrides o
      WHERE o.path = 'catalog_revision_id' AND o.value->>'value' IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM spacecraft_config_overrides p
          WHERE p.mission_id = o.mission_id AND p.spacecraft_id = o.spacecraft_id
            AND p.path = 'composition_id')
      ORDER BY 2, 3
      """)

    Enum.map(rows, fn [org, mission, spacecraft, catalog, reason, revision] ->
      %{
        organization_id: org,
        mission_id: mission,
        spacecraft_id: spacecraft,
        catalog: catalog,
        reason: reason,
        set_in_revision: revision
      }
    end)
  end

  defp pin_override(repo, override, composition_id, now),
    do:
      repo.query!(
        """
        INSERT INTO spacecraft_config_overrides
          (organization_id, mission_id, spacecraft_id, path, value, reason, set_by,
           set_in_revision, set_at)
        VALUES ($1, $2, $3, 'composition_id', $4, $5, $6, $7, $8)
        ON CONFLICT (mission_id, spacecraft_id, path) DO NOTHING
        """,
        [
          override.organization_id,
          override.mission_id,
          override.spacecraft_id,
          %{"value" => composition_id},
          override.reason,
          @actor,
          override.set_in_revision,
          now
        ]
      )

  # The pinned catalog revision's one-layer composition, which must exist in its own tenant.
  defp composition!(repo, org, mission, catalog) do
    with [[layer_id]] <- single_layer(repo, org, mission, catalog),
         composition_id = Compositions.id(org, mission, [{layer_id, "/"}]),
         true <- exists?(repo, org, mission, composition_id) do
      composition_id
    else
      _missing ->
        raise "pin migration: catalog revision #{catalog} (#{org}/#{mission}) has no one-layer " <>
                "composition; refusing to leave its pin without one"
    end
  end

  defp single_layer(repo, org, mission, catalog) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT l.layer_id
        FROM catalog_revisions c
        JOIN mission_model_revision_layers rl ON rl.revision_id = c.mission_model_revision_id
        JOIN mission_model_layers l ON l.layer_id = rl.layer_id
        WHERE c.catalog_revision_id = $3 AND c.organization_id = $1 AND c.mission_id = $2
          AND l.organization_id = $1 AND l.mission_id = $2 AND l.layer_kind = 'imported'
        """,
        [org, mission, catalog]
      )

    rows
  end

  defp exists?(repo, org, mission, composition_id) do
    %{rows: [[count]]} =
      repo.query!(
        """
        SELECT count(*) FROM mission_model_compositions
        WHERE organization_id = $1 AND mission_id = $2 AND composition_id = $3
        """,
        [org, mission, composition_id]
      )

    count == 1
  end
end
