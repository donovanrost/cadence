defmodule Cadence.CompositionFixtures do
  @moduledoc """
  Fixtures for mission compositions (D1 #541, D3 #544): revision status, a copy of a fixture's
  revision under another compiler version (as an older or a rival compiler would have made it),
  and a link for it.
  """

  alias Cadence.Catalog.CompositionPins
  alias Cadence.MissionModels.Compositions
  alias Cadence.Repo

  @doc "The catalog revision's one-layer composition: what a profile or override pins (D3, #544)."
  def pin!(org, mission_id, catalog_revision_id) do
    {:ok, composition_id} =
      CompositionPins.for_catalog_revision(org, mission_id, catalog_revision_id)

    composition_id
  end

  def approve!(revision_id), do: set_status!([revision_id], "approved")

  def set_status!(revision_ids, status),
    do:
      Repo.query!(
        "UPDATE mission_model_revisions SET status = $2 WHERE revision_id = ANY($1)",
        [revision_ids, status]
      )

  # A copy of the fixture's revision under another id and compiler version, with its layers and a
  # catalog revision naming it: as if an older (or a rival) compiler had made it.
  def copy_revision!(c, version) do
    new_id = "mission_model_revision:copy-#{System.unique_integer([:positive])}"

    copy = fn table, key, changes ->
      Repo.query!(
        "INSERT INTO #{table} SELECT (jsonb_populate_record(NULL::#{table}, " <>
          "to_jsonb(t) || $2::jsonb)).* FROM #{table} t WHERE t.#{key} = $1",
        [c.revision_id, changes]
      )
    end

    copy.("mission_model_revisions", "revision_id", %{
      "revision_id" => new_id,
      "compiler_version" => version,
      "content_sha256" => Base.encode16(:crypto.hash(:sha256, new_id), case: :lower)
    })

    copy.("mission_model_revision_layers", "revision_id", %{"revision_id" => new_id})

    run_id = "catalog_import_run:copy-#{new_id}"

    Repo.query!(
      "INSERT INTO catalog_import_runs SELECT (jsonb_populate_record(NULL::catalog_import_runs, " <>
        "to_jsonb(t) || jsonb_build_object('import_run_id', $2::text))).* " <>
        "FROM catalog_import_runs t WHERE t.import_run_id = $1",
      [c.catalog.import_run_id, run_id]
    )

    Repo.query!(
      # Inserted after the original, so the composition's provenance (the earliest catalog
      # revision, CompositionPins.catalog_revision_for/3) stays the original import.
      "INSERT INTO catalog_revisions SELECT (jsonb_populate_record(NULL::catalog_revisions, " <>
        "to_jsonb(t) || jsonb_build_object('catalog_revision_id', $2::text, " <>
        "'mission_model_revision_id', $3::text, 'revision_number', t.revision_number + $5::int, " <>
        "'revision_label', t.revision_label || ' (copy ' || $5::text || ')', " <>
        "'inserted_at', t.inserted_at + interval '1 second', " <>
        "'import_run_id', $4::text))).* " <>
        "FROM catalog_revisions t WHERE t.catalog_revision_id = $1",
      [
        c.catalog.catalog_revision_id,
        "catalog_revision:copy-#{new_id}",
        new_id,
        run_id,
        1000 + System.unique_integer([:positive])
      ]
    )

    new_id
  end

  @doc "Links `revision_id` (of its own compiler version) to `composition_id` at a NULL head."
  def link!(c, composition_id, revision_id) do
    Repo.query!(
      """
      INSERT INTO mission_model_effective_revisions
        (organization_id, mission_id, composition_id, authored_head, compiler_version,
         revision_id, inserted_at)
      SELECT organization_id, mission_id, $1, NULL, compiler_version, revision_id, clock_timestamp()
      FROM mission_model_revisions WHERE revision_id = $2
      """,
      [composition_id, revision_id]
    )

    {:ok, _} = Compositions.fetch(c.org, c.mid, composition_id)
    :ok
  end
end
