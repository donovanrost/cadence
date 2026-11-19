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
      occurrence_count: inputs.templates |> Enum.map(&fan_out/1) |> Enum.sum(),
      eligible_occurrence_count:
        inputs.templates |> Enum.map(&eligible_count(&1, inputs.window)) |> Enum.sum()
    }
  end

  # Occurrences × targeted spacecraft (a template fans out per spacecraft).
  defp fan_out(t), do: length(t.occurrences) * length(t.spacecraft_ids)

  defp eligible_count(t, window) do
    # Days an older version's requirement still serves (kept) or closed (done) aren't eligible;
    # its days this version regenerates are (DECISIONS #86).
    existing =
      for row <- t.existing_occurrences,
          Map.get(row, :outcome) != "generate",
          into: MapSet.new(),
          do: {row.at, row.spacecraft_id}

    for at <- t.occurrences,
        {starts, ends} = RequirementSchedule.window(t.version.schedule_document, at),
        DateTime.before?(starts, window.horizon_end) and
          DateTime.after?(ends, window.horizon_start),
        spacecraft_id <- t.spacecraft_ids,
        not MapSet.member?(existing, {DateTime.to_unix(at, :microsecond), spacecraft_id}),
        reduce: 0 do
      count -> count + 1
    end
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
      name: v.name,
      target: v.target_document,
      spacecraft_id: v.spacecraft_id,
      spacecraft_count: length(t.spacecraft_ids),
      occurrence_count: fan_out(t),
      maximum_occurrences: v.catch_up_policy_document["maximum_occurrences_per_run"],
      maximum_lookback_seconds: v.catch_up_policy_document["maximum_lookback_seconds"]
    }
  end
end
