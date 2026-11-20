defmodule Cadence.MissionModels.CompositionBackfill do
  @moduledoc """
  The one-to-one migration of D1 (#541; design §7), run by migration 20261120060000 in its own
  transaction. Every catalog revision's mission-model revision is already a one-import compile at
  '/' (#456 keeps it byte-identical), so each becomes:

  - a one-layer composition `[{layer_id, "/"}]`, written by a system actor that counts no one
    for separation (mms-security M1; #513's seed rule);
  - a link from that composition (authored head NULL) to the SAME revision row, when the revision
    has no blocking diagnostic (§2: a revision with one isn't usable, so it gets no link).

  Nothing is written to `mission_model_revisions`: approvals stay exactly as they are (CB-4).
  Raw SQL only, so a later change to the app's schemas can't change what this migration did.

  It fails loudly rather than leave an approved revision without the composition E1's approve
  needs: an approved revision that isn't a single imported layer in its own tenant raises.
  Anything else that can't be migrated (an unapproved revision of another shape) is skipped and
  counted.
  """

  alias Cadence.MissionModels.Compositions

  @actor %{
    "actor_kind" => "system",
    "system_id" => "migration:20261120060000",
    "name" => "Composition migration (#541)"
  }

  @doc "Migrates every catalog revision's model revision; returns the counts."
  @spec run(module()) :: %{
          composed: non_neg_integer(),
          linked: non_neg_integer(),
          skipped: [binary()]
        }
  def run(repo) do
    now = DateTime.utc_now()

    repo
    |> revisions()
    |> Enum.reduce(%{composed: 0, linked: 0, skipped: []}, fn revision, acc ->
      case layers(repo, revision) do
        [%{layer_id: layer_id, kind: "imported", organization_id: org}]
        when org == revision.organization_id ->
          compose(repo, revision, layer_id, now, acc)

        other ->
          refuse_or_skip(revision, other, acc)
      end
    end)
  end

  defp compose(repo, revision, layer_id, now, acc) do
    %{organization_id: org, mission_id: mission, revision_id: revision_id} = revision
    composition_id = Compositions.id(org, mission, [{layer_id, "/"}])

    repo.query!(
      """
      INSERT INTO mission_model_compositions
        (organization_id, mission_id, composition_id, created_by, inserted_at)
      VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING
      """,
      [org, mission, composition_id, @actor, now]
    )

    repo.query!(
      """
      INSERT INTO mission_model_composition_layers
        (organization_id, mission_id, composition_id, layer_id, mount, position)
      VALUES ($1, $2, $3, $4, '/', 0) ON CONFLICT DO NOTHING
      """,
      [org, mission, composition_id, layer_id]
    )

    acc = %{acc | composed: acc.composed + 1}

    if usable?(repo, revision_id) do
      repo.query!(
        """
        INSERT INTO mission_model_effective_revisions
          (organization_id, mission_id, composition_id, authored_head, revision_id, inserted_at)
        VALUES ($1, $2, $3, NULL, $4, $5) ON CONFLICT DO NOTHING
        """,
        [org, mission, composition_id, revision_id, now]
      )

      %{acc | linked: acc.linked + 1}
    else
      acc
    end
  end

  defp refuse_or_skip(%{status: "approved", revision_id: id}, shape, _acc),
    do:
      raise(
        "composition migration: approved revision #{id} isn't one imported layer in its own " <>
          "tenant (#{inspect(shape)}); refusing to leave its approval without a composition"
      )

  defp refuse_or_skip(%{revision_id: id}, _shape, acc), do: %{acc | skipped: [id | acc.skipped]}

  defp revisions(repo) do
    %{rows: rows} =
      repo.query!("""
      SELECT DISTINCT r.organization_id, r.mission_id, r.revision_id, r.status
      FROM catalog_revisions c
      JOIN mission_model_revisions r ON r.revision_id = c.mission_model_revision_id
      WHERE r.organization_id IS NOT NULL
      ORDER BY r.revision_id
      """)

    Enum.map(rows, fn [org, mission, revision_id, status] ->
      %{organization_id: org, mission_id: mission, revision_id: revision_id, status: status}
    end)
  end

  defp layers(repo, %{revision_id: revision_id}) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT l.layer_id, l.layer_kind, l.organization_id
        FROM mission_model_revision_layers rl
        JOIN mission_model_layers l ON l.layer_id = rl.layer_id
        WHERE rl.revision_id = $1
        ORDER BY rl.position
        """,
        [revision_id]
      )

    Enum.map(rows, fn [layer_id, kind, org] ->
      %{layer_id: layer_id, kind: kind, organization_id: org}
    end)
  end

  defp usable?(repo, revision_id) do
    %{rows: [[blocking]]} =
      repo.query!(
        "SELECT count(*) FROM mission_model_diagnostics WHERE revision_id = $1 AND severity = 'error'",
        [revision_id]
      )

    blocking == 0
  end
end
