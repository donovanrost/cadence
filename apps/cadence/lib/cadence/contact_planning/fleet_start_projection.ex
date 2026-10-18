defmodule Cadence.ContactPlanning.FleetStartProjection do
  @moduledoc "Semantic, bounded review projection for manual fleet creation."
  alias Cadence.ContactPlanning.{FleetStartInputs, RequirementSchedule}

  def policy(version) do
    %{
      id: version.fleet_planning_policy_id,
      version: version.version,
      content_sha256: version.content_sha256,
      max_horizon_seconds: version.horizon_document["max_horizon_seconds"],
      requirement_concurrency: version.horizon_document["requirement_concurrency"],
      provider_search_concurrency: version.horizon_document["provider_search_concurrency"],
      max_contacts: version.budget_quota_document["max_contacts"],
      max_estimated_cost_micros: version.budget_quota_document["max_estimated_cost_micros"],
      currency: version.budget_quota_document["currency"]
    }
  end

  def review(inputs, pages) do
    %{
      contract_version: 1,
      context: inputs.context,
      window: FleetStartInputs.window_reference(inputs.window),
      policy: policy(inputs.policy),
      evidence: inputs.evidence,
      requirements: page(inputs.requirements, pages["requirements_page"], &requirement/1),
      templates: page(inputs.templates, pages["templates_page"], &template/1),
      occurrence_count: inputs.templates |> Enum.map(&length(&1.occurrences)) |> Enum.sum(),
      eligible_occurrence_count:
        inputs.templates |> Enum.map(&eligible_count(&1, inputs.window)) |> Enum.sum()
    }
  end

  defp eligible_count(t, window) do
    existing = MapSet.new(t.existing_occurrences, & &1.at)

    Enum.count(t.occurrences, fn at ->
      {starts, ends} = RequirementSchedule.window(t.version.schedule_document, at)

      not MapSet.member?(existing, DateTime.to_unix(at, :microsecond)) and
        DateTime.before?(starts, window.horizon_end) and
        DateTime.after?(ends, window.horizon_start)
    end)
  end

  defp page(entries, page, mapper) do
    %{
      page: page,
      total: length(entries),
      more: length(entries) > page * 25,
      entries: entries |> Enum.slice((page - 1) * 25, 25) |> Enum.map(mapper)
    }
  end

  defp requirement({_, v}) do
    %{
      id: v.contact_requirement_id,
      version: v.version,
      content_sha256: v.content_sha256,
      spacecraft_id: v.spacecraft_id,
      earliest_start: DateTime.to_iso8601(v.earliest_start),
      latest_end: DateTime.to_iso8601(v.latest_end),
      priority: Atom.to_string(v.priority),
      success_measure: Atom.to_string(v.success_measure)
    }
  end

  defp template(t) do
    v = t.version

    %{
      id: v.contact_requirement_template_id,
      version: v.version,
      content_sha256: v.content_sha256,
      spacecraft_id: v.spacecraft_id,
      occurrence_count: length(t.occurrences),
      maximum_occurrences: v.catch_up_policy_document["maximum_occurrences_per_run"],
      maximum_lookback_seconds: v.catch_up_policy_document["maximum_lookback_seconds"]
    }
  end
end
