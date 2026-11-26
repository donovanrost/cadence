defmodule Cadence.Management.Contacts.Store.TemplateDayCounts do
  @moduledoc "SQL grouping for a template edit’s decided-day review."

  import Ecto.Query

  alias Cadence.Management.Contacts.Store.{
    ContactRequirementOccurrenceRow,
    ContactRequirementRow,
    ContactRequirementVersionRow
  }

  alias Cadence.Repo

  @doc "The decided occurrence lists and their UTC day and requirement totals."
  def list(org, mission, template_id, current_version, since, opts) do
    opts
    |> classified_days(org, mission, template_id, current_version, since)
    |> summarize()
    |> Repo.all()
  end

  defp classified_days(opts, org, mission, template_id, current_version, since) do
    latest = latest_occurrences(org, mission, template_id, current_version, since)
    taken_up = Keyword.fetch!(opts, :taken_up)
    [versioned, left_target] = Keyword.fetch!(opts, :superseded_prefixes)
    now = Keyword.fetch!(opts, :now)

    from(o in subquery(latest),
      join: r in ContactRequirementRow,
      on:
        r.organization_id == ^org and r.mission_id == ^mission and
          r.contact_requirement_id == o.requirement_id,
      join: v in ContactRequirementVersionRow,
      on:
        v.organization_id == r.organization_id and v.mission_id == r.mission_id and
          v.contact_requirement_id == r.contact_requirement_id and v.version == r.current_version,
      left_join: p in subquery(taken_up),
      on: p.requirement_id == r.contact_requirement_id,
      select: %{
        at: o.at,
        spacecraft_id: o.spacecraft_id,
        kind:
          fragment(
            """
            CASE
              WHEN ? = 'active' AND (? IS NOT NULL OR ? <= ?) THEN 'planned_or_started'
              WHEN ? = 'closed' THEN 'closed'
              WHEN ? = 'canceled' AND NOT (starts_with(coalesce(?, ''), ?) OR starts_with(coalesce(?, ''), ?)) THEN 'canceled'
            END
            """,
            r.lifecycle_state,
            p.requirement_id,
            v.earliest_start,
            type(^now, :utc_datetime_usec),
            r.lifecycle_state,
            r.lifecycle_state,
            r.lifecycle_reason,
            ^versioned,
            r.lifecycle_reason,
            ^left_target
          )
      }
    )
  end

  defp latest_occurrences(org, mission, template_id, current_version, since) do
    from(o in ContactRequirementOccurrenceRow,
      where:
        o.organization_id == ^org and o.mission_id == ^mission and
          o.contact_requirement_template_id == ^template_id and
          o.contact_requirement_template_version <= ^current_version and
          o.generation_state == "generated" and o.occurrence_at >= ^since,
      distinct: [o.occurrence_at, o.spacecraft_id],
      order_by: [desc: o.contact_requirement_template_version],
      select: %{
        at: o.occurrence_at,
        spacecraft_id: o.spacecraft_id,
        requirement_id: o.generated_contact_requirement_id
      }
    )
  end

  defp summarize(classified) do
    times =
      from(o in subquery(classified),
        where: not is_nil(o.kind),
        group_by: [o.kind, o.at],
        select: %{
          kind: o.kind,
          at: o.at,
          requirements: count(),
          spacecraft_ids:
            fragment("array_agg(? ORDER BY ? COLLATE \"C\")", o.spacecraft_id, o.spacecraft_id)
        }
      )

    from(o in subquery(times),
      group_by: o.kind,
      select:
        {o.kind,
         fragment(
           "jsonb_agg(jsonb_build_object('occurrence_at', ? AT TIME ZONE 'UTC', 'date', ?::date, 'spacecraft_ids', ?) ORDER BY ?)",
           o.at,
           o.at,
           o.spacecraft_ids,
           o.at
         ), count(fragment("?::date", o.at), :distinct),
         fragment("sum(?)::bigint", o.requirements),
         fragment("array_agg(DISTINCT ?::date ORDER BY ?::date)", o.at, o.at)}
    )
  end
end
