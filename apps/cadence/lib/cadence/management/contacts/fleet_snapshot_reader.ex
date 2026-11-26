defmodule Cadence.Management.Contacts.FleetSnapshotReader do
  @moduledoc false

  import Ecto.Query

  alias Cadence.ContactPlanning.ContactOpportunitySnapshot

  alias Cadence.Management.Contacts.Store.{
    ContactOpportunitySnapshotRow,
    ContactPlanningSearchRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @run_batch_size 2_000
  @snapshot_fields [
    :contact_opportunity_snapshot_id,
    :contact_planning_run_id,
    :contact_planning_search_id,
    :organization_id,
    :mission_id,
    :contact_requirement_id,
    :contact_requirement_version,
    :provider_opportunity_ref,
    :starts_at,
    :ends_at,
    :expires_at,
    :availability,
    :estimated_capacity_document,
    :synthetic,
    :normalized_opportunity_document,
    :evaluation_document,
    :eligible,
    :content_sha256,
    :captured_at
  ]
  @optimizer_fields @snapshot_fields -- [:normalized_opportunity_document, :evaluation_document]

  @doc "Reads the immutable snapshots needed for an optimization without retaining provider payloads."
  def list(organization_id, mission_id, run_ids) do
    organization_id
    |> stream(mission_id, run_ids)
    |> Enum.to_list()
  end

  @doc "Loads bounded batches of persisted snapshots as the allocator consumes them."
  def stream(organization_id, mission_id, run_ids) do
    run_ids
    |> Stream.chunk_every(@run_batch_size)
    |> Stream.flat_map(fn ids ->
      # Each bounded group drives the snapshot index by run ID. Keep this lookup local
      # to the requested run so a fresh fleet cannot turn each batch into a mission scan.
      snapshots =
        from(snapshot in ContactOpportunitySnapshotRow,
          where: snapshot.contact_planning_run_id == parent_as(:requested).id,
          offset: 0
        )

      rows =
        from(requested in fragment("(SELECT unnest(?::text[]) AS id)", ^Enum.uniq(ids)),
          as: :requested
        )
        |> join(:inner_lateral, [], snapshot in subquery(snapshots), on: true)
        |> join(:inner, [_, snapshot], search in ContactPlanningSearchRow,
          on: search.contact_planning_search_id == snapshot.contact_planning_search_id
        )
        |> where(
          [_, snapshot],
          snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id
        )
        |> select([_, snapshot, _search], map(snapshot, ^@optimizer_fields))
        |> select_merge([_, snapshot, search], %{
          starts_at: type(snapshot.starts_at, :utc_datetime_usec),
          ends_at: type(snapshot.ends_at, :utc_datetime_usec),
          expires_at: type(snapshot.expires_at, :utc_datetime_usec),
          captured_at: type(snapshot.captured_at, :utc_datetime_usec),
          route_binding_document:
            fragment(
              "jsonb_build_object('spacecraft_id', ? #>> '{value,spacecraft_id}', 'provider_id', ? #>> '{value,provider_id}', 'provider_account_grant_id', ? #>> '{value,provider_account_grant_id}', 'route_key', ? #>> '{value,route_key}')",
              search.route_binding_document,
              search.route_binding_document,
              search.route_binding_document,
              search.route_binding_document
            ),
          normalized_opportunity_document:
            fragment(
              "jsonb_build_object('ground_station_ref', ? #>> '{value,ground_station_ref}', 'antenna_or_service_pool_ref', ? #>> '{value,antenna_or_service_pool_ref}', 'estimated_cost', ? #> '{value,estimated_cost}', 'extensions', jsonb_build_object('estimated_cost', ? #> '{value,extensions,estimated_cost}', 'cost', ? #> '{value,extensions,cost}'))",
              snapshot.normalized_opportunity_document,
              snapshot.normalized_opportunity_document,
              snapshot.normalized_opportunity_document,
              snapshot.normalized_opportunity_document,
              snapshot.normalized_opportunity_document
            ),
          evaluation_document:
            fragment(
              "CASE WHEN ? THEN '{}'::jsonb ELSE ? END",
              snapshot.eligible,
              snapshot.evaluation_document
            )
        })
        |> Repo.all()

      Enum.map(rows, &compact(&1, false))
    end)
  end

  def list_by_ids(organization_id, mission_id, snapshot_ids) do
    snapshot_ids
    |> Enum.chunk_every(@run_batch_size)
    |> Enum.flat_map(fn ids ->
      ContactOpportunitySnapshotRow
      |> join(:inner, [snapshot], search in assoc(snapshot, :search))
      |> where(
        [snapshot],
        snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
          snapshot.contact_opportunity_snapshot_id in ^ids
      )
      |> select([snapshot, _search], map(snapshot, ^@optimizer_fields))
      |> select_merge([snapshot, search], %{
        route_binding_document: search.route_binding_document,
        normalized_opportunity_document: fragment("'{}'::jsonb"),
        evaluation_document:
          fragment(
            "jsonb_build_object('warnings', COALESCE(? #> '{value,warnings}', '[]'::jsonb))",
            snapshot.evaluation_document
          )
      })
      |> Repo.all()
      |> Enum.map(&compact(&1, true))
    end)
  end

  def snapshot_ids_for_runs(organization_id, mission_id, run_ids) do
    ContactOpportunitySnapshotRow
    |> where(
      [snapshot],
      snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
        snapshot.contact_planning_run_id in ^run_ids
    )
    |> select([snapshot], {snapshot.starts_at, snapshot.contact_opportunity_snapshot_id})
    |> Repo.all()
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  def planning_run_ids_for_snapshots(organization_id, mission_id, snapshot_ids) do
    ContactOpportunitySnapshotRow
    |> where(
      [snapshot],
      snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
        snapshot.contact_opportunity_snapshot_id in ^snapshot_ids
    )
    |> select([snapshot], snapshot.contact_planning_run_id)
    |> distinct(true)
    |> Repo.all()
  end

  defp compact(row, plan?) do
    route = JsonDocument.unwrap_value(row.route_binding_document)
    opportunity = JsonDocument.unwrap_value(row.normalized_opportunity_document)
    capacity = JsonDocument.unwrap_value(row.estimated_capacity_document)

    extensions =
      opportunity
      |> Map.get("extensions", %{})
      |> Map.take(["estimated_cost", "cost"])

    normalized =
      opportunity
      |> Map.take(["ground_station_ref", "antenna_or_service_pool_ref", "estimated_cost"])
      |> Map.put("extensions", extensions)

    ContactOpportunitySnapshot.new(%{
      contact_opportunity_snapshot_id: row.contact_opportunity_snapshot_id,
      contact_planning_run_id: row.contact_planning_run_id,
      contact_planning_search_id: row.contact_planning_search_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_requirement_id: row.contact_requirement_id,
      contact_requirement_version: row.contact_requirement_version,
      provider_opportunity_ref: row.provider_opportunity_ref,
      starts_at: row.starts_at,
      ends_at: row.ends_at,
      expires_at: row.expires_at,
      availability: row.availability,
      estimated_capacity_document:
        if(plan?, do: capacity, else: Map.take(capacity, ["bytes", "data_volume_bytes"])),
      synthetic: row.synthetic,
      route_binding_document:
        if(plan?,
          do: route,
          else:
            Map.take(route, [
              "spacecraft_id",
              "provider_id",
              "provider_account_grant_id",
              "route_key"
            ])
        ),
      normalized_opportunity_document: normalized,
      provider_evidence_document: %{},
      evaluation_document:
        if(row.eligible and not plan?,
          do: %{},
          else: JsonDocument.unwrap_value(row.evaluation_document)
        ),
      eligible: row.eligible,
      content_sha256: row.content_sha256,
      captured_at: row.captured_at
    })
  end
end
