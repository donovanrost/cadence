defmodule Cadence.MissionModelCatalogNaming do
  @moduledoc """
  Test setup: gives a mission-model revision compiled straight from layers
  (`MissionModels.compile_layers/2`, no import) a catalog revision that names it, as every
  revision made in production has: an approved and activated model revision must be one a
  catalog revision names (`Catalog.ModelRevisionNaming`, director 11-17).

  Don't use it in the guard's own tests (`MissionModels.CatalogNamedRevisionTest`): they need a
  revision no catalog revision names.

  Since #541/#542 it also gives the revision what an import gives it: its one-layer mission
  composition at '/' (a system actor that counts no one, as a migrated composition) and the link
  that names the revision, so approval and promotion (`MissionModels.require_composition/3`) see
  it as an import's own.
  """

  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, ImportRun, ImportRunRow, Revision, RevisionRow}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Compositions, EffectiveRevisionRow}
  alias Cadence.Repo

  @system %{"actor_kind" => "system", "system_id" => "cadence-test", "name" => "Cadence test"}

  @doc "Names `mission_model_revision_id` in a new catalog revision; returns the catalog revision."
  def name!(organization_id, mission_id, mission_model_revision_id) do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, database} =
      Catalog.create_database(organization_id, mission_id, %{
        name: "Fixture model " <> suffix,
        slug: "fixture-model-" <> suffix,
        catalog_family: :combined,
        default_importer_key: "cadence_yaml"
      })

    {:ok, artifact} =
      Catalog.persist_artifact(
        organization_id,
        Artifact.new(%{
          mission_id: mission_id,
          catalog_database_id: database.catalog_database_id,
          catalog_family: :combined,
          artifact_name: "fixture-model.yaml",
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          source_artifact: "packets: []\ncommands: []\n# " <> suffix <> "\n"
        })
      )

    now = DateTime.utc_now()

    run =
      ImportRun.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        catalog_database_id: database.catalog_database_id,
        artifact_id: artifact.artifact_id,
        catalog_family: :combined,
        importer_key: "cadence_yaml",
        importer_version: 1,
        status: :completed,
        result_document: %{"mission_model" => %{"revision_id" => mission_model_revision_id}},
        started_at: now,
        completed_at: now
      })

    Repo.insert!(ImportRunRow.changeset(run))

    catalog_revision =
      %{
        organization_id: organization_id,
        mission_id: mission_id,
        catalog_database_id: database.catalog_database_id,
        revision_number: 1,
        revision_label: "Fixture",
        catalog_family: :combined,
        artifact_id: artifact.artifact_id,
        import_run_id: run.import_run_id,
        mission_model_revision_id: mission_model_revision_id,
        content_sha256: artifact.content_sha256,
        created_by: %{},
        metadata: %{}
      }
      |> Revision.new()
      |> RevisionRow.changeset()
      |> Repo.insert!()
      |> RevisionRow.to_domain()

    compose!(organization_id, mission_id, mission_model_revision_id)
    catalog_revision
  end

  # An import's own composition: its single layer at '/', linked to THIS revision as an import
  # links its own compile (`Compositions.effective_revision/5`'s `compiled:`). The link is written
  # directly, not recompiled: a test may compile with options a plain recompile wouldn't repeat.
  defp compose!(organization_id, mission_id, revision_id) do
    {:ok, %{layer_ids: [layer_id], compiler_version: compiler_version}} =
      MissionModels.fetch_revision(organization_id, mission_id, revision_id)

    {:ok, composition} =
      Compositions.insert_or_get(organization_id, mission_id, [{layer_id, "/"}], @system)

    Repo.insert!(
      %EffectiveRevisionRow{
        organization_id: organization_id,
        mission_id: mission_id,
        composition_id: composition.composition_id,
        authored_head: nil,
        revision_id: revision_id,
        # #559: a link per compiler version, the revision's own (its composite FK).
        compiler_version: compiler_version
      },
      on_conflict: :nothing
    )

    :ok
  end
end
