defmodule Cadence.ContactPlanning.TemplateDayReview do
  @moduledoc """
  The template edit's dry run (U48, DECISIONS #86): which of the template's days an edit won't
  regenerate. The SQL groups the latest generated requirement of each slot using the same
  lifecycle rules as `TemplateDays.classify/6`.

  The days looked at are the template's generated occurrences from the current version's catch-up
  lookback onward (older days aren't materialized again). Groups, each a list of
  `%{occurrence_at, date, spacecraft_ids}` (one per occurrence instant, oldest first):

    * `planned_or_started`: kept (a plan past draft holds it, or its window has begun);
    * `closed`, `canceled`: done by an operator. Days canceled by supersession or by leaving the
      target are regenerated, so they aren't listed.
  """

  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirementTemplates, TemplateDays}

  alias Cadence.Management.Contacts.Store.TemplateDayCounts

  @empty %{planned_or_started: [], closed: [], canceled: []}
  @empty_counts %{days: 0, requirements: 0, dates: [], first_date: nil, last_date: nil}

  @spec decided(binary(), binary(), binary(), DateTime.t()) :: map()
  def decided(org, mission, template_id, %DateTime{} = now),
    do: review(org, mission, template_id, now).decided

  @doc "The existing occurrence lists and exact UTC day and requirement counts per group."
  def review(org, mission, template_id, %DateTime{} = now) do
    case ContactRequirementTemplates.fetch(org, mission, template_id) do
      {:ok, template, version} ->
        lookback = version.catch_up_policy_document["maximum_lookback_seconds"] || 0
        since = DateTime.add(now, -lookback, :second)

        org
        |> TemplateDayCounts.list(mission, template_id, template.current_version, since,
          now: now,
          taken_up: ContactPlans.taken_up_requirements_query(org, mission),
          superseded_prefixes: TemplateDays.superseded_prefixes()
        )
        |> summarize()

      {:error, _not_found} ->
        empty_review()
    end
  end

  defp summarize(groups) do
    groups
    |> Enum.reduce(empty_review(), fn {kind, entries, days, requirements, dates}, result ->
      key = group_key(kind)
      dates = Enum.map(dates, &Date.to_iso8601/1)

      counts = %{
        days: days,
        requirements: requirements,
        first_date: List.first(dates),
        last_date: List.last(dates),
        dates: if(days <= 3, do: dates, else: [])
      }

      result
      |> put_in([:decided, key], Enum.map(entries, &entry/1))
      |> put_in([:decided_counts, key], counts)
    end)
  end

  defp group_key("planned_or_started"), do: :planned_or_started
  defp group_key("closed"), do: :closed
  defp group_key("canceled"), do: :canceled

  defp empty_review,
    do: %{
      decided: @empty,
      decided_counts: Map.new(@empty, fn {kind, _} -> {kind, @empty_counts} end)
    }

  defp entry(row) do
    {:ok, at, _} = DateTime.from_iso8601(row["occurrence_at"])
    at = at |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)
    %{occurrence_at: at, date: row["date"], spacecraft_ids: row["spacecraft_ids"]}
  end
end
