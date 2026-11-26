defmodule Cadence.Management.Contacts.Store.PlanDemandCounts do
  @moduledoc "Coverage totals from the requirement versions pinned by one plan version."

  import Ecto.Query

  alias Cadence.Management.Contacts.Store.ContactRequirementVersionRow
  alias Cadence.Repo

  def load(org, mission, evaluations, unmet) do
    grouped = per_spacecraft(org, mission, evaluations)

    grouped
    |> subquery()
    |> select([g], %{
      rule_total: count(),
      rule_met: filter(count(), g.rule_met),
      spacecraft_uncovered: filter(count(), not g.rule_met),
      contacts_short:
        fragment(
          "COALESCE(sum(greatest(0, ? - ?)) FILTER (WHERE NOT ?), 0)::bigint",
          g.need,
          g.have,
          g.rule_met
        )
    })
    |> Repo.one!()
    |> Map.put(:gaps, unmet_spacecraft(org, mission, unmet))
  end

  defp per_spacecraft(org, mission, evaluations) do
    document = %{"rows" => evaluations}

    ContactRequirementVersionRow
    |> where([v], v.organization_id == ^org and v.mission_id == ^mission)
    |> join(
      :inner,
      [v],
      e in fragment(
        "(SELECT * FROM jsonb_to_recordset(?->'rows') AS e(contact_requirement_id text, contact_requirement_version integer, satisfied boolean, facts jsonb))",
        type(^document, :map)
      ),
      on:
        v.contact_requirement_id == e.contact_requirement_id and
          v.version == e.contact_requirement_version
    )
    |> group_by([v, _e], v.spacecraft_id)
    |> select([v, e], %{
      rule_met: fragment("bool_and(coalesce(?, false))", e.satisfied),
      have: sum(fragment("COALESCE((?->>'selected_count')::integer, 0)", e.facts)),
      need: sum(v.contact_count)
    })
  end

  defp unmet_spacecraft(_org, _mission, []), do: 0

  defp unmet_spacecraft(org, mission, unmet) do
    document = %{"rows" => unmet}

    from(
      e in fragment(
        "(SELECT * FROM jsonb_to_recordset(?->'rows') AS e(contact_requirement_id text, contact_requirement_version integer))",
        type(^document, :map)
      ),
      left_join: v in ContactRequirementVersionRow,
      on:
        v.organization_id == ^org and v.mission_id == ^mission and
          v.contact_requirement_id == e.contact_requirement_id and
          v.version == e.contact_requirement_version,
      select:
        fragment(
          "count(DISTINCT ?) + CASE WHEN count(*) FILTER (WHERE ? IS NULL) > 0 THEN 1 ELSE 0 END",
          v.spacecraft_id,
          v.spacecraft_id
        )
    )
    |> Repo.one!()
  end
end
