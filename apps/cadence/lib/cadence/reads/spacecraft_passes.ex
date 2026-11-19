defmodule Cadence.Reads.SpacecraftPasses do
  @moduledoc """
  Investigate's Passes tab, P1 coverage and the queued counts for P3 (ux Investigate.md
  24a160b8). The passes themselves come from `GET /passes` (P2/P3) and Pass review rows (P4).

  - `last_contact`: the most recent pass that has ended and flew (`active`/`completed`), within
    7 days.
  - `next_contact` (within 7 days), `passes_next_24h` and `longest_gap`: booked passes
    (`confirmed`/`active`, as in Now's queue). The gap is the longest stretch of `[now, now + 24 h]` with no booked pass,
    edges included. `none_within_6h` is U35's caution.
  - `contact_rule`: the spacecraft's active contact requirements whose window overlaps today
    (UTC). Each window's `have` is the booked or flown passes inside it, capped at its count:
    `met` when every window has its count, `short` otherwise, `none` without a rule.
  - `queued`: `%{pass_id => count}` of queued, unfinished command groups bound to the pass (> 0).
  """

  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.Control.UplinkReadiness.Groups
  alias Cadence.Reads.{CommandGroups, Passes}
  alias Cadence.SpacecraftStore

  @day_s 86_400
  @horizon_s @day_s
  @caution_s 6 * 3_600
  @lookback_s 7 * @day_s
  @booked ~w(confirmed active)
  @flown ~w(active completed)

  @spec load(binary(), binary(), binary(), DateTime.t()) ::
          {:ok, map()} | {:error, :spacecraft_not_found}
  def load(org, mission, spacecraft_id, now \\ DateTime.utc_now()) do
    with {:ok, _craft} <- SpacecraftStore.fetch_spacecraft(org, mission, spacecraft_id) do
      rules = rules(org, mission, spacecraft_id, now)
      {from, to} = span(rules, now)

      passes =
        org
        |> Passes.load(mission, from, to, %{spacecraft_id: spacecraft_id, limit: 2_000})
        |> Map.fetch!(:passes)

      {:ok,
       %{
         observed_at: now,
         coverage: coverage(passes, rules, now),
         queued: queued(org, mission, passes, now)
       }}
    end
  end

  @doc false
  @spec coverage([map()], [map()], DateTime.t()) :: map()
  def coverage(passes, rules, now) do
    until = DateTime.add(now, @horizon_s)

    booked =
      passes |> Enum.filter(&(&1.state in @booked)) |> Enum.sort_by(& &1.starts_at, DateTime)

    ahead = Enum.filter(booked, &(after?(&1.starts_at, now) and before?(&1.starts_at, until)))
    next = Enum.find(booked, &after?(&1.starts_at, now))

    %{
      last_contact: last_contact(passes, now),
      next_contact: next && %{pass_id: next.id, station: next.station, aos_at: next.starts_at},
      passes_next_24h: length(ahead),
      longest_gap: longest_gap(booked, now, until),
      none_within_6h: is_nil(next) or DateTime.diff(next.starts_at, now) > @caution_s,
      contact_rule: contact_rule(rules, passes)
    }
  end

  defp last_contact(passes, now) do
    passes
    |> Enum.filter(&(&1.state in @flown and not after?(&1.ends_at, now)))
    |> Enum.max_by(& &1.ends_at, DateTime, fn -> nil end)
    |> case do
      nil -> nil
      pass -> %{pass_id: pass.id, station: pass.station, los_at: pass.ends_at}
    end
  end

  # Walks the booked passes overlapping [now, until] and keeps the widest uncovered stretch.
  defp longest_gap(booked, now, until) do
    {cursor, best} =
      booked
      |> Enum.filter(&(after?(&1.ends_at, now) and before?(&1.starts_at, until)))
      |> Enum.reduce({now, nil}, fn pass, {cursor, best} ->
        {latest(cursor, pass.ends_at), widest(best, cursor, pass.starts_at)}
      end)

    widest(best, cursor, until)
  end

  defp widest(best, from, to) do
    seconds = DateTime.diff(to, from)

    if seconds > 0 and (is_nil(best) or seconds > best.seconds),
      do: %{seconds: seconds, from: from, to: to},
      else: best
  end

  defp contact_rule([], _passes), do: %{state: :none, have: 0, need: 0, rules: []}

  defp contact_rule(rules, passes) do
    counted = Enum.filter(passes, &(&1.state in (@booked ++ @flown)))

    windows =
      Enum.map(rules, fn rule ->
        inside =
          Enum.count(counted, fn pass ->
            not before?(pass.starts_at, rule.window.from) and
              not after?(pass.ends_at, rule.window.to)
          end)

        Map.merge(rule, %{have: min(inside, rule.need), met: inside >= rule.need})
      end)

    %{
      state: if(Enum.all?(windows, & &1.met), do: :met, else: :short),
      have: Enum.sum_by(windows, & &1.have),
      need: Enum.sum_by(windows, & &1.need),
      rules: windows
    }
  end

  defp rules(org, mission, spacecraft_id, now) do
    day_start = DateTime.new!(DateTime.to_date(now), ~T[00:00:00], "Etc/UTC")
    day_end = DateTime.add(day_start, @day_s)

    org
    |> ContactRequirements.list(mission, lifecycle_state: :active)
    |> Enum.filter(fn {_requirement, version} ->
      version.spacecraft_id == spacecraft_id and before?(version.earliest_start, day_end) and
        after?(version.latest_end, day_start)
    end)
    |> Enum.map(fn {requirement, version} ->
      %{
        requirement_id: requirement.contact_requirement_id,
        version: version.version,
        text: rule_text(version),
        window: %{from: version.earliest_start, to: version.latest_end},
        need: version.contact_count || 1
      }
    end)
  end

  # Same wording as the contact plan's rules (Reads.ContactPlanOverview).
  defp rule_text(version) do
    count = version.contact_count || 1
    direction = version.service_direction && to_string(version.service_direction)
    "#{count} #{direction || "contact"} #{if count == 1, do: "contact", else: "contacts"}"
  end

  # Passes from 7 days back (last contact) to 7 days ahead (next contact), widened to cover
  # today's rule windows.
  defp span(rules, now) do
    from = Enum.reduce(rules, DateTime.add(now, -@lookback_s), &earliest(&2, &1.window.from))
    to = Enum.reduce(rules, DateTime.add(now, @lookback_s), &latest(&2, &1.window.to))

    {latest(from, DateTime.add(now, -2 * @lookback_s)),
     earliest(to, DateTime.add(now, 2 * @lookback_s))}
  end

  defp queued(org, mission, passes, now) do
    by_contact =
      for pass <- passes,
          is_binary(pass.scheduled_contact_id),
          after?(pass.ends_at, now),
          into: %{},
          do: {pass.scheduled_contact_id, pass.id}

    group_ids =
      if by_contact == %{},
        do: [],
        else:
          for(
            %{finished: false, id: id} <- CommandGroups.list(org, mission, nil, states: [:queued]),
            do: id
          )

    org
    |> groups(mission, group_ids)
    |> Enum.flat_map(fn {_id, %{targets: targets}} ->
      targets
      |> Enum.map(&target_contact/1)
      |> Enum.filter(&Map.has_key?(by_contact, &1))
      |> Enum.uniq()
    end)
    |> Enum.frequencies_by(&Map.fetch!(by_contact, &1))
  end

  defp groups(_org, _mission, []), do: %{}
  defp groups(org, mission, ids), do: Groups.for_command_groups(org, mission, ids)

  defp target_contact(%{contact: %{scheduled_contact_id: id}}), do: id
  defp target_contact(%{next_contact: %{scheduled_contact_id: id}}), do: id
  defp target_contact(_target), do: nil

  defp after?(a, b), do: DateTime.compare(a, b) == :gt
  defp before?(a, b), do: DateTime.compare(a, b) == :lt
  defp earliest(a, b), do: if(before?(b, a), do: b, else: a)
  defp latest(a, b), do: if(after?(b, a), do: b, else: a)
end
