defmodule Cadence.Applications.SpacecraftConfiguration.Assignments do
  @moduledoc "Versioned spacecraft assignments to immutable, identity-free configuration artifacts."

  import Ecto.Query

  alias Cadence.Applications.SpacecraftConfiguration.AssignmentRow
  alias Cadence.Ids
  alias Cadence.Platform.ContentBasis
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo

  @artifacts "spacecraft_configuration_artifacts"
  @heads "spacecraft_configuration_heads"
  @endpoint "telemetry_source_endpoint_id"
  @scope [:organization_id, :mission_id, :spacecraft_id]
  # Bound the number of PostgreSQL parameters per INSERT while keeping ordinary fleets in one batch.
  @batch_size 4_000

  def saved?(org, mission) do
    Repo.exists?(heads(org, mission))
  end

  def latest_many(_org, _mission, []), do: %{}

  def latest_many(org, mission, ids) do
    org
    |> headed_assignments(mission)
    |> where([head], head.spacecraft_id in ^ids)
    |> resolved()
    |> Map.new(&{&1.spacecraft_id, &1})
  end

  def latest_for_mission(org, mission) do
    org |> heads(mission) |> head_references() |> Repo.all()
  end

  def latest_references(org, mission, ids) do
    org
    |> heads(mission)
    |> where([head], head.spacecraft_id in ^ids)
    |> head_references()
    |> Repo.all()
    |> Map.new(&{&1.spacecraft_id, &1.configuration_revision_id})
  end

  def catalog_usage_entries(org, mission) do
    org
    |> headed_assignments(mission)
    |> with_artifact()
    |> where([artifact: artifact], not is_nil(artifact.catalog_revision_id))
    |> select([assignment: row, artifact: artifact], %{
      spacecraft_id: row.spacecraft_id,
      catalog_revision_id: artifact.catalog_revision_id
    })
    |> Repo.all()
  end

  def fetch_many(_org, _mission, []), do: %{}

  def fetch_many(org, mission, ids) do
    org
    |> scoped(mission)
    |> where([assignment: row], row.configuration_revision_id in ^ids)
    |> resolved()
    |> Map.new(&{&1.configuration_revision_id, &1})
  end

  def history(org, mission, spacecraft) do
    org
    |> scoped(mission)
    |> where([assignment: row], row.spacecraft_id == ^spacecraft)
    |> order_by([assignment: row], desc: row.version)
    |> limit(20)
    |> resolved()
  end

  def new(mission, spacecraft, version, document, actor, evidence) do
    %AssignmentRow{
      organization_id: mission.organization_id,
      mission_id: mission.mission_id,
      spacecraft_id: spacecraft,
      configuration_revision_id: Ids.new("spacecraft_configuration"),
      version: version,
      catalog_revision_id: document["catalog_revision_id"],
      composition_id: evidence[:composition_id],
      effective_revision_id: evidence[:effective_revision_id],
      change_set_id: evidence[:change_set_id],
      change_set_revision: evidence[:change_set_revision],
      document: document,
      source_endpoint_id: document[@endpoint],
      content_sha256: ContentHash.term_sha256(document),
      created_by: actor,
      inserted_at: DateTime.utc_now()
    }
  end

  @doc "Appends assignments and advances their heads under the caller's mission lock and transaction."
  def append([]), do: []

  def append(rows) do
    pairs = Enum.map(rows, &encode/1)

    pairs
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq_by(&{&1.organization_id, &1.mission_id, &1.sha256})
    |> insert_batches(@artifacts,
      on_conflict: :nothing,
      conflict_target: [:organization_id, :mission_id, :sha256]
    )

    assignments = Enum.map(pairs, &elem(&1, 0))

    assignments
    |> Enum.map(&Map.take(&1, AssignmentRow.__schema__(:fields)))
    |> insert_batches(AssignmentRow, [])

    assignments
    |> Enum.map(&Map.take(&1, [:configuration_revision_id | @scope]))
    |> insert_batches(@heads,
      on_conflict: {:replace, [:configuration_revision_id]},
      conflict_target: @scope
    )

    assignments
  end

  defp encode(row) do
    document = Map.delete(row.document, @endpoint)

    sha =
      ContentBasis.digest("spacecraft_configuration", 1,
        document: document,
        composition_id: row.composition_id,
        effective_revision_id: row.effective_revision_id
      )

    {%{row | artifact_sha256: sha},
     %{
       organization_id: row.organization_id,
       mission_id: row.mission_id,
       sha256: sha,
       document: document,
       catalog_revision_id: row.catalog_revision_id,
       composition_id: row.composition_id,
       effective_revision_id: row.effective_revision_id
     }}
  end

  defp insert_batches(rows, table, opts) do
    rows
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(&Repo.insert_all(table, &1, opts))
  end

  defp scoped(org, mission) do
    from(row in AssignmentRow,
      as: :assignment,
      where: row.organization_id == ^org and row.mission_id == ^mission
    )
  end

  defp heads(org, mission) do
    from(head in @heads, where: head.organization_id == ^org and head.mission_id == ^mission)
  end

  defp head_references(query) do
    select(query, [head], map(head, [:spacecraft_id, :configuration_revision_id]))
  end

  defp headed_assignments(org, mission) do
    from(head in heads(org, mission),
      join: row in AssignmentRow,
      as: :assignment,
      on: row.configuration_revision_id == head.configuration_revision_id
    )
  end

  defp with_artifact(query) do
    from([assignment: row] in query,
      join: artifact in @artifacts,
      as: :artifact,
      on:
        artifact.sha256 == row.artifact_sha256 and
          artifact.organization_id == row.organization_id and
          artifact.mission_id == row.mission_id
    )
  end

  defp resolved(query) do
    query
    |> with_artifact()
    |> select([assignment: row, artifact: artifact], {
      row,
      artifact.document,
      artifact.catalog_revision_id,
      artifact.composition_id,
      artifact.effective_revision_id
    })
    |> Repo.all()
    |> Enum.map(fn {row, document, catalog, composition, revision} ->
      document = Map.put(document, @endpoint, row.source_endpoint_id)

      %{
        row
        | document: document,
          content_sha256: ContentHash.term_sha256(document),
          catalog_revision_id: catalog,
          composition_id: composition,
          effective_revision_id: revision
      }
    end)
  end
end
