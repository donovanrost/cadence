defmodule Cadence.Reads.ApplicationSurfaces.Planning.RequirementDetailProjection do
  @moduledoc false

  def project(
        scope,
        requirement,
        version,
        selected,
        query,
        pages
      ) do
    %{
      contract_version: 1,
      context: %{
        organization_id: scope.organization_id,
        mission_id: requirement.mission_id,
        actor_id: if(scope.user, do: scope.user.user_id)
      },
      requirement: %{
        id: requirement.contact_requirement_id,
        version: version.version,
        content_sha256: version.content_sha256,
        current_version: requirement.current_version,
        lifecycle_state: Atom.to_string(requirement.lifecycle_state),
        direction: Atom.to_string(version.service_direction),
        priority: Atom.to_string(version.priority),
        intent: version.contact_intent,
        outcome: outcome(version),
        rationale: version.rationale,
        earliest_start: DateTime.to_iso8601(version.earliest_start),
        latest_end: DateTime.to_iso8601(version.latest_end)
      },
      query: query,
      selected_run: if(selected, do: run(selected)),
      versions: page(pages.versions, query["versions_page"], &version/1),
      runs: page(pages.runs, query["runs_page"], &run/1),
      searches: page(pages.searches, query["searches_page"], &search/1),
      opportunities: page(pages.opportunities, query["opportunities_page"], &opportunity/1)
    }
  end

  defp page(result, number, project),
    do: %{page: number, more: result.more?, entries: Enum.map(result.entries, project)}

  defp version(version),
    do: %{
      id: version.contact_requirement_version_id,
      version: version.version,
      content_sha256: version.content_sha256,
      created_at: DateTime.to_iso8601(version.created_at)
    }

  defp run(run),
    do: %{
      id: run.contact_planning_run_id,
      version: run.contact_requirement_version,
      state: Atom.to_string(run.lifecycle_state),
      started_at: DateTime.to_iso8601(run.started_at)
    }

  defp search(search),
    do: %{
      id: search.contact_planning_search_id,
      route_key: preview(search.route_key),
      provider: preview(search.provider_display_name || "Provider route"),
      outcome: Atom.to_string(search.outcome),
      opportunity_count: search.opportunity_count,
      content_sha256: search.content_sha256
    }

  defp opportunity(snapshot),
    do: %{
      id: snapshot.contact_opportunity_snapshot_id,
      run_id: snapshot.contact_planning_run_id,
      requirement_id: snapshot.contact_requirement_id,
      version: snapshot.contact_requirement_version,
      provider: preview(snapshot.route_binding_document["provider_display_name"] || "Provider"),
      station:
        preview(
          snapshot.normalized_opportunity_document["ground_station_ref"] || "Unspecified station"
        ),
      starts_at: DateTime.to_iso8601(snapshot.starts_at),
      ends_at: DateTime.to_iso8601(snapshot.ends_at),
      expires_at: DateTime.to_iso8601(snapshot.expires_at),
      availability: Atom.to_string(snapshot.availability),
      eligible: snapshot.eligible,
      synthetic: snapshot.synthetic,
      content_sha256: snapshot.content_sha256
    }

  # Labels are previews, not provider evidence documents. Identity and hashes
  # remain exact; no readiness, credentials or raw provider errors cross here.
  defp preview(value) when is_binary(value) do
    points = String.codepoints(value)
    if length(points) > 120, do: Enum.join(Enum.take(points, 120)) <> "…", else: value
  end

  defp preview(_), do: "Unavailable label"

  defp outcome(%{success_measure: :any_contact}), do: "Any eligible contact"

  defp outcome(%{success_measure: :minimum_duration} = v),
    do: "At least #{v.minimum_duration_seconds} seconds"

  defp outcome(%{success_measure: :minimum_data_volume} = v),
    do: "At least #{v.minimum_data_volume_bytes} bytes"

  defp outcome(%{success_measure: :contact_count} = v),
    do: "#{v.contact_count} contacts · at least #{v.minimum_separation_seconds} seconds apart"
end
