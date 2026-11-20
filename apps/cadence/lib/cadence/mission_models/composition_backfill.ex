defmodule Cadence.MissionModels.CompositionBackfill do
  @moduledoc """
  The one-to-one migration of D1 (#541; design §7), run by migration 20261120060000 in its own
  transaction. Every catalog revision's mission-model revision is already a one-import compile at
  '/' (#456 keeps it byte-identical), so each becomes:

  - a one-layer composition `[{layer_id, "/"}]`, written by a system actor that counts no one
    for separation (mms-security M1; #513's seed rule);
  - a link from that composition (authored head NULL) at the revision's OWN compiler version to
    the SAME revision row, when the revision has no blocking diagnostic (§2). Two revisions of one
    layer made by different compiler versions each get their own link (domain, mms-security on
    #559).

  Nothing is written to `mission_model_revisions`: approvals stay exactly as they are (CB-4).
  The writes are raw SQL, so a later change to the app's schemas can't change what this migration
  did. The one app function it calls, `Compositions.id/3`, is pinned by its golden test (#108).

  It fails loudly, never leaving an approval without the link E1's approve needs (mms-security):
  - an approved revision that isn't a single imported layer in its own mission raises;
  - an approved revision with a blocking diagnostic raises;
  - any link collision raises: another revision already linked at the same composition, head and
    compiler version;
  - after the loop, `guard!/1` raises if any approved revision a catalog revision names has no
    link, naming the ids.

  Anything else that can't be linked (an unapproved revision of another shape, or with a blocking
  diagnostic) is skipped and listed. `linked` counts rows actually inserted, so a re-run counts 0.
  """

  alias Cadence.MissionModels.Compositions

  @actor %{"actor_kind" => "system", "system_id" => "migration:20261120060000"}

  @doc "Migrates every catalog revision's model revision, then runs `guard!/1`; returns the counts."
  @spec run(module()) :: %{
          composed: non_neg_integer(),
          linked: non_neg_integer(),
          skipped: [binary()]
        }
  def run(repo) do
    now = DateTime.utc_now()

    counts =
      repo
      |> revisions()
      |> Enum.reduce(%{composed: 0, linked: 0, skipped: []}, fn revision, acc ->
        migrate(repo, revision, now, acc)
      end)

    guard!(repo)
    counts
  end

  defp migrate(repo, revision, now, acc) do
    case layers(repo, revision) do
      [%{layer_id: layer_id, kind: "imported", organization_id: org, mission_id: mission}]
      when org == revision.organization_id and mission == revision.mission_id ->
        compose(repo, revision, layer_id, now, acc)

      other ->
        refuse_or_skip(revision, {:shape, other}, acc)
    end
  end

  @doc """
  Raises if any approved revision that a catalog revision names has no link (mms-security on
  #559): the backfill's own post-condition, checked inside the migration's transaction.
  """
  @spec guard!(module()) :: :ok
  def guard!(repo) do
    %{rows: rows} =
      repo.query!("""
      SELECT DISTINCT r.revision_id
      FROM catalog_revisions c
      JOIN mission_model_revisions r ON r.revision_id = c.mission_model_revision_id
      LEFT JOIN mission_model_effective_revisions e ON e.revision_id = r.revision_id
      WHERE r.organization_id IS NOT NULL AND r.status = 'approved' AND e.revision_id IS NULL
      ORDER BY r.revision_id
      """)

    case rows do
      [] ->
        :ok

      ids ->
        raise "composition migration: approved revisions without a link: " <>
                Enum.join(List.flatten(ids), ", ")
    end
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

    if usable?(repo, revision_id),
      do: link(repo, revision, composition_id, now, acc),
      else: refuse_or_skip(revision, :blocking_diagnostics, acc)
  end

  defp link(repo, revision, composition_id, now, acc) do
    %{organization_id: org, mission_id: mission, revision_id: revision_id} = revision
    version = revision.compiler_version

    %{num_rows: inserted} =
      repo.query!(
        """
        INSERT INTO mission_model_effective_revisions
          (organization_id, mission_id, composition_id, authored_head, compiler_version,
           revision_id, inserted_at)
        VALUES ($1, $2, $3, NULL, $4, $5, $6) ON CONFLICT DO NOTHING
        """,
        [org, mission, composition_id, version, revision_id, now]
      )

    case {inserted, linked_revision(repo, org, mission, composition_id, version)} do
      {1, _linked} -> %{acc | linked: acc.linked + 1}
      {0, ^revision_id} -> acc
      {0, other} -> collision!(revision, composition_id, other)
    end
  end

  defp linked_revision(repo, org, mission, composition_id, version) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT revision_id FROM mission_model_effective_revisions
        WHERE organization_id = $1 AND mission_id = $2 AND composition_id = $3
          AND authored_head IS NULL AND compiler_version = $4
        """,
        [org, mission, composition_id, version]
      )

    case rows do
      [[revision_id]] -> revision_id
      [] -> nil
    end
  end

  defp collision!(revision, composition_id, other),
    do:
      raise(
        "composition migration: revision #{revision.revision_id} and #{inspect(other)} both " <>
          "compose #{composition_id} at compiler version #{revision.compiler_version}; " <>
          "refusing to choose one"
      )

  defp refuse_or_skip(%{status: "approved", revision_id: id}, why, _acc),
    do:
      raise(
        "composition migration: approved revision #{id} can't be linked (#{inspect(why)}); " <>
          "refusing to leave its approval without a composition"
      )

  defp refuse_or_skip(%{revision_id: id}, _why, acc), do: %{acc | skipped: [id | acc.skipped]}

  # Approved first, so an approved revision is never the one a collision finds already linked.
  defp revisions(repo) do
    %{rows: rows} =
      repo.query!("""
      SELECT r.organization_id, r.mission_id, r.revision_id, r.status, r.compiler_version
      FROM mission_model_revisions r
      WHERE r.organization_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM catalog_revisions c WHERE c.mission_model_revision_id = r.revision_id)
      ORDER BY (r.status = 'approved') DESC, r.revision_id
      """)

    Enum.map(rows, fn [org, mission, revision_id, status, version] ->
      %{
        organization_id: org,
        mission_id: mission,
        revision_id: revision_id,
        status: status,
        compiler_version: version
      }
    end)
  end

  defp layers(repo, %{revision_id: revision_id}) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT l.layer_id, l.layer_kind, l.organization_id, l.mission_id
        FROM mission_model_revision_layers rl
        JOIN mission_model_layers l ON l.layer_id = rl.layer_id
        WHERE rl.revision_id = $1
        ORDER BY rl.position
        """,
        [revision_id]
      )

    Enum.map(rows, fn [layer_id, kind, org, mission] ->
      %{layer_id: layer_id, kind: kind, organization_id: org, mission_id: mission}
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
