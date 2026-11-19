defmodule Cadence.Reads.EventLog.RawKinds do
  @moduledoc """
  U69 A9b: the Timeline's raw-kind filter and its picker.

    * `raw_kind=` is a comma list (at most #{20}) of exact raw kinds (`command_released`) or
      prefixes ending in `*` (`command_*`). Exact-only lists go to SQL through the timeline's
      `:kind` option; prefixes are matched per page, like the console `kind` filter.
    * `list/4`: the raw kinds in a window with their console kind and count, most frequent first,
      from the density count query (no event rows loaded) plus the merged configuration
      revisions and off-plan bookings.
  """

  alias Cadence.Reads.{ConfigRevisionEvents, EventDensity, EventLog, OffPlanBookingEvents}
  alias Cadence.Reads.EventLog.DensityCounts

  @max 20
  @item ~r/^[a-z0-9_]+\*?$/

  @type pattern :: {:exact, binary()} | {:prefix, binary()}

  @spec parse(binary() | nil) :: {:ok, [pattern()] | nil} | {:error, binary()}
  def parse(nil), do: {:ok, nil}
  def parse(""), do: {:ok, nil}

  def parse(value) when is_binary(value) do
    items = value |> String.split(",") |> Enum.map(&String.trim/1)

    cond do
      length(items) > @max -> {:error, "at most #{@max} raw kinds"}
      Enum.all?(items, &Regex.match?(@item, &1)) -> {:ok, Enum.map(items, &pattern/1)}
      true -> {:error, "must be raw kinds (a-z, 0-9, _), each optionally ending in *"}
    end
  end

  defp pattern(item) do
    case String.split_at(item, -1) do
      {prefix, "*"} -> {:prefix, prefix}
      _exact -> {:exact, item}
    end
  end

  @doc "The exact kinds when every pattern is exact (pushed to SQL), else `nil`."
  @spec exact([pattern()] | nil) :: [binary()] | nil
  def exact(nil), do: nil

  def exact(patterns) do
    if Enum.all?(patterns, &match?({:exact, _}, &1)),
      do: Enum.map(patterns, &elem(&1, 1)),
      else: nil
  end

  @spec selected?(term(), [pattern()] | nil) :: boolean()
  def selected?(_raw_kind, nil), do: true

  def selected?(raw_kind, patterns) do
    raw = to_string(raw_kind)

    Enum.any?(patterns, fn
      {:exact, kind} -> raw == kind
      {:prefix, prefix} -> String.starts_with?(raw, prefix)
    end)
  end

  @doc "The picker: `[%{raw_kind, kind, count}]` in `[from, to)`, most frequent first."
  @spec list(binary(), binary(), DateTime.t(), DateTime.t()) :: [map()]
  def list(organization_id, mission_id, from, to) do
    span = max(DateTime.diff(to, from), 1)

    counted =
      organization_id
      |> EventDensity.groups(mission_id, from, to, span, false)
      |> Enum.map(fn group ->
        {group.kind, elem(DensityCounts.classify(group), 0), group.count}
      end)

    window = [from_occurred_at: from, to_occurred_at: to]

    merged =
      (ConfigRevisionEvents.entries(organization_id, mission_id, window) ++
         OffPlanBookingEvents.entries(organization_id, mission_id, window))
      |> Enum.map(&{to_string(&1.kind), elem(EventLog.classify_entry(&1), 0), 1})

    (counted ++ merged)
    |> Enum.group_by(fn {raw, kind, _count} -> {raw, kind} end, &elem(&1, 2))
    |> Enum.map(fn {{raw, kind}, counts} ->
      %{raw_kind: raw, kind: kind, count: Enum.sum(counts)}
    end)
    |> Enum.sort_by(&{-&1.count, &1.raw_kind})
  end
end
