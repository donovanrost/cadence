defmodule Cadence.ContactPlanning.TemplateDayReview do
  @moduledoc """
  The template edit's dry run (U48, DECISIONS #86): which of the template's days an edit won't
  regenerate, by `TemplateDays.classify/6` with the next version number, so the preview, the
  materialize and the fleet start agree.

  The days looked at are the template's generated occurrences from the current version's catch-up
  lookback onward (older days aren't materialized again). Groups, each a list of
  `%{occurrence_at, date, spacecraft_ids}` (one per occurrence instant, oldest first):

    * `planned_or_started`: kept (a plan past draft holds it, or its window has begun);
    * `closed`, `canceled`: done by an operator. Days canceled by supersession or by leaving the
      target are regenerated, so they aren't listed.
  """

  alias Cadence.ContactPlanning.{ContactRequirementTemplates, TemplateDays}

  @empty %{planned_or_started: [], closed: [], canceled: []}

  @spec decided(binary(), binary(), binary(), DateTime.t()) :: map()
  def decided(org, mission, template_id, %DateTime{} = now) do
    case ContactRequirementTemplates.fetch(org, mission, template_id) do
      {:ok, template, version} ->
        lookback = version.catch_up_policy_document["maximum_lookback_seconds"] || 0
        since = DateTime.add(now, -lookback, :second)
        days = ContactRequirementTemplates.generated_days(org, mission, template_id, since)

        org
        |> TemplateDays.classify(mission, template_id, template.current_version + 1, days,
          now: now
        )
        |> group(days)

      {:error, _not_found} ->
        @empty
    end
  end

  defp group(classified, days) do
    by_group =
      days
      |> Enum.flat_map(fn {at, spacecraft_id} ->
        case group_of(classified[TemplateDays.key(at, spacecraft_id)]) do
          nil -> []
          name -> [{name, at, spacecraft_id}]
        end
      end)
      |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))

    Map.new(@empty, fn {name, []} -> {name, entries(Map.get(by_group, name, []))} end)
  end

  defp group_of(%{outcome: :kept}), do: :planned_or_started
  defp group_of(%{outcome: :done, why: :closed}), do: :closed
  defp group_of(%{outcome: :done, why: :canceled}), do: :canceled
  defp group_of(_generate), do: nil

  # One entry per instant; sorted here, spacecraft bytewise (#56).
  defp entries(pairs) do
    pairs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {at, _ids} -> DateTime.to_unix(at, :microsecond) end)
    |> Enum.map(fn {at, ids} ->
      %{
        occurrence_at: at,
        date: at |> DateTime.to_date() |> Date.to_iso8601(),
        spacecraft_ids: ids |> Enum.uniq() |> Enum.sort()
      }
    end)
  end
end
