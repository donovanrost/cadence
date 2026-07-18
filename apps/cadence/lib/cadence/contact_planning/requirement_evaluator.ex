defmodule Cadence.ContactPlanning.RequirementEvaluator do
  @moduledoc "Pure, deterministic Contact Requirement opportunity and coverage evaluation."

  alias Cadence.ContactPlanning.{ContactOpportunitySnapshot, ContactRequirementVersion}

  @spec evaluate_opportunity(ContactRequirementVersion.t(), map(), map(), keyword()) :: map()
  def evaluate_opportunity(
        %ContactRequirementVersion{} = requirement,
        opportunity,
        route,
        opts \\ []
      )
      when is_map(opportunity) and is_map(route) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    starts_at = datetime(opportunity, "starts_at")
    ends_at = datetime(opportunity, "ends_at")
    expires_at = datetime(opportunity, "expires_at")
    duration_seconds = DateTime.diff(ends_at, starts_at, :second)
    estimated_volume_bytes = estimated_volume(opportunity["estimated_capacity"])

    hard_failures =
      [
        failure(
          DateTime.before?(starts_at, requirement.earliest_start),
          "outside_requirement_window",
          "Opportunity starts before the acceptable window."
        ),
        failure(
          DateTime.after?(ends_at, requirement.latest_end),
          "outside_requirement_window",
          "Opportunity ends after the acceptable window."
        ),
        failure(
          requirement.service_direction != :downlink,
          "direction_not_executable",
          "Only downlink Requirement planning is executable in Stage 4."
        ),
        failure(
          opportunity["availability"] == "unavailable",
          "provider_unavailable",
          "Provider marks this opportunity unavailable."
        ),
        failure(
          not DateTime.after?(expires_at, now),
          "opportunity_expired",
          "Provider opportunity has expired."
        ),
        failure(
          is_integer(requirement.minimum_duration_seconds) and
            duration_seconds < requirement.minimum_duration_seconds,
          "minimum_duration_not_met",
          "Opportunity is shorter than the required minimum duration."
        ),
        failure(
          excluded?(requirement.provider_constraints_document, route["provider_id"]),
          "provider_not_allowed",
          "Provider is outside this Requirement's allowed set."
        ),
        failure(
          excluded?(requirement.station_constraints_document, opportunity["ground_station_ref"]),
          "station_not_allowed",
          "Ground station is outside this Requirement's allowed set."
        ),
        failure(
          requirement.success_measure == :minimum_data_volume and
            is_nil(estimated_volume_bytes),
          "estimated_volume_unknown",
          "Provider did not supply the volume estimate required for planning."
        )
      ]
      |> Enum.reject(&is_nil/1)

    warnings =
      [
        warning(
          is_integer(requirement.preferred_duration_seconds) and
            duration_seconds < requirement.preferred_duration_seconds and hard_failures == [],
          "preferred_duration_not_met",
          "Opportunity meets the minimum but is shorter than the preferred duration."
        ),
        warning(
          is_nil(estimated_volume_bytes) and
            requirement.success_measure != :minimum_data_volume,
          "estimated_volume_unavailable",
          "Provider did not supply an estimated data volume."
        )
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "eligible" => hard_failures == [],
      "hard_failures" => hard_failures,
      "warnings" => warnings,
      "facts" => %{
        "duration_seconds" => duration_seconds,
        "estimated_volume_bytes" => estimated_volume_bytes,
        "expected_volume_known" => is_integer(estimated_volume_bytes),
        "provider_allowed" =>
          not excluded?(requirement.provider_constraints_document, route["provider_id"]),
        "station_allowed" =>
          not excluded?(
            requirement.station_constraints_document,
            opportunity["ground_station_ref"]
          ),
        "expires_at" => DateTime.to_iso8601(expires_at)
      }
    }
  end

  @spec evaluate_selection(ContactRequirementVersion.t(), [ContactOpportunitySnapshot.t()], [
          map()
        ]) ::
          map()
  def evaluate_selection(%ContactRequirementVersion{} = requirement, snapshots, searches \\ [])
      when is_list(snapshots) and is_list(searches) do
    ordered = Enum.sort_by(snapshots, & &1.starts_at, DateTime)
    eligible = Enum.filter(ordered, & &1.eligible)
    durations = Enum.map(eligible, &DateTime.diff(&1.ends_at, &1.starts_at, :second))
    volumes = Enum.map(eligible, &estimated_volume(&1.estimated_capacity_document))
    unknown_volume? = Enum.any?(volumes, &is_nil/1)
    known_volume = volumes |> Enum.reject(&is_nil/1) |> Enum.sum()
    separation_failures = separation_failures(eligible, requirement.minimum_separation_seconds)

    hard_failures =
      [
        selection_failure(
          length(eligible) < requirement.contact_count,
          "contact_count_not_met",
          "The selection has fewer eligible contacts than required."
        ),
        selection_failure(
          requirement.success_measure == :minimum_data_volume and unknown_volume?,
          "aggregate_volume_unknown",
          "At least one selected opportunity lacks the required volume estimate."
        ),
        selection_failure(
          requirement.success_measure == :minimum_data_volume and not unknown_volume? and
            known_volume < requirement.minimum_data_volume_bytes,
          "minimum_data_volume_not_met",
          "Selected opportunities do not meet the minimum expected data volume."
        )
      ]
      |> Enum.reject(&is_nil/1)
      |> Kernel.++(separation_failures)

    search_failures =
      searches
      |> Enum.filter(&(search_value(&1, :outcome) in [:failed, :not_ready]))
      |> Enum.map(fn search ->
        %{
          "code" => "provider_search_unavailable",
          "route_key" => search_value(search, :route_key),
          "outcome" => search_value(search, :outcome) |> to_string()
        }
      end)

    %{
      "satisfied" => hard_failures == [] and eligible != [],
      "hard_failures" => hard_failures,
      "search_failures" => search_failures,
      "facts" => %{
        "selected_count" => length(snapshots),
        "eligible_count" => length(eligible),
        "required_contact_count" => requirement.contact_count,
        "aggregate_duration_seconds" => Enum.sum(durations),
        "aggregate_estimated_volume_bytes" => known_volume,
        "aggregate_volume_complete" => not unknown_volume?
      }
    }
  end

  defp excluded?(constraints, ref) do
    allowed = Map.get(constraints, "allowed", [])
    excluded = Map.get(constraints, "excluded", [])

    ref in excluded or (allowed != [] and ref not in allowed)
  end

  defp estimated_volume(%{"bytes" => bytes}) when is_integer(bytes) and bytes >= 0, do: bytes

  defp estimated_volume(%{"data_volume_bytes" => bytes})
       when is_integer(bytes) and bytes >= 0,
       do: bytes

  defp estimated_volume(_capacity), do: nil

  defp datetime(map, key) do
    case map[key] do
      %DateTime{} = item -> item
      item when is_binary(item) -> elem(DateTime.from_iso8601(item), 1)
    end
  end

  defp failure(true, code, message), do: %{"code" => code, "message" => message}
  defp failure(false, _code, _message), do: nil
  defp warning(condition, code, message), do: failure(condition, code, message)
  defp selection_failure(condition, code, message), do: failure(condition, code, message)

  defp separation_failures([_one_or_none], _minimum), do: []
  defp separation_failures([], _minimum), do: []

  defp separation_failures(snapshots, minimum) do
    snapshots
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [first, second] ->
      gap = DateTime.diff(second.starts_at, first.ends_at, :second)

      cond do
        gap < 0 ->
          [%{"code" => "selected_contacts_overlap", "gap_seconds" => gap}]

        gap < minimum ->
          [
            %{
              "code" => "minimum_separation_not_met",
              "gap_seconds" => gap,
              "required_seconds" => minimum
            }
          ]

        true ->
          []
      end
    end)
  end

  defp search_value(search, key) when is_struct(search), do: Map.fetch!(search, key)

  defp search_value(search, key) do
    Map.get(search, key, Map.get(search, Atom.to_string(key)))
  end
end
