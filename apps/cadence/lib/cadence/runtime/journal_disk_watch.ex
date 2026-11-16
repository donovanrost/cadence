defmodule Cadence.Runtime.JournalDiskWatch do
  @moduledoc """
  The ingress journal's DISK, as the `ingress_backpressure` monitor watches it (ux U66). Pure state:
  the monitor feeds it a disk reading, the streams on the disk and whether any journal is failing
  for lack of space; it keeps the open item and recent resolutions.

  Each stream has its own cap (one contact, ux U47's `journal_near_full`); nothing caps their sum,
  and a full disk stops telemetry from every pass at once. The item opens at 70 % (caution), turns
  critical at 90 %, and clears below 60 % (no flapping). An unreadable disk (`:unknown`) changes
  nothing: an open item stays as last read.
  """

  @caution 70.0
  @critical 90.0
  @clear 60.0
  @rate_window_s 3_600
  @resolved_keep_s 120

  @type t :: map()

  @spec new() :: t()
  def new,
    do: %{
      level: nil,
      raised_at: nil,
      reading: nil,
      samples: [],
      streams: [],
      refusing: false,
      refused_since: nil,
      refused_spell: nil,
      resolved: []
    }

  @doc """
  The next state from a reading: `{state, changed?}` (changed when the item opened, changed level,
  started or stopped refusing, or cleared: the monitor then publishes).
  """
  @spec sample(t(), {:ok, map()} | :unknown, [map()], boolean(), DateTime.t()) :: {t(), boolean()}
  def sample(state, :unknown, _streams, refusing?, now),
    do: refusing(state, refusing?, now)

  def sample(state, {:ok, %{percent: percent} = reading}, streams, refusing?, now) do
    samples =
      [{now, reading.used_bytes} | state.samples]
      |> Enum.filter(fn {at, _used} -> DateTime.diff(now, at) <= @rate_window_s end)

    level = level(state.level, percent)
    {state, refusing_changed?} = refusing(state, refusing?, now)

    opened_or_moved? = level != state.level

    state =
      cond do
        is_nil(level) and not is_nil(state.level) ->
          resolve(state, now)

        is_nil(state.level) and not is_nil(level) ->
          %{state | raised_at: now}

        true ->
          state
      end

    {%{state | level: level, reading: reading, samples: samples, streams: streams},
     opened_or_moved? or refusing_changed?}
  end

  @doc "The open item as `mission_id` sees it (its own holders named), or nil."
  @spec view(t(), binary()) :: nil | map()
  def view(%{level: nil}, _mission_id), do: nil

  def view(state, mission_id) do
    {own, others} = Enum.split_with(state.streams, &(&1.mission_id == mission_id))
    own = by_contact(own)
    rate = rate_per_hour(state.samples)

    %{
      level: state.level,
      raised_at: state.raised_at,
      percent: state.reading.percent,
      used_bytes: state.reading.used_bytes,
      size_bytes: state.reading.size_bytes,
      rate_bytes_per_hour: rate,
      eta_full_s: eta_full_s(state.reading, rate),
      holders: Enum.take(own, 3),
      more_count: max(length(own) - 3, 0),
      other_missions_bytes: others |> Enum.map(& &1.bytes) |> Enum.sum(),
      refusing: state.refusing,
      refused_since: state.refused_since
    }
  end

  @doc "Recent resolutions: `[%{resolved_at, refused_from, refused_to}]` (kept 2 minutes)."
  @spec resolved(t(), DateTime.t()) :: [map()]
  def resolved(state, now) do
    cutoff = DateTime.add(now, -@resolved_keep_s, :second)
    Enum.filter(state.resolved, &(DateTime.compare(&1.resolved_at, cutoff) == :gt))
  end

  @doc "The missions the disk item concerns (whose Now to refresh): every stream's mission."
  @spec missions(t()) :: [binary()]
  def missions(state),
    do: state.streams |> Enum.map(& &1.mission_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  # A contact's paths each have a stream: one holder per contact, largest first.
  defp by_contact(streams) do
    streams
    |> Enum.group_by(& &1.realized_contact_id)
    |> Enum.map(fn {contact, entries} ->
      %{realized_contact_id: contact, bytes: entries |> Enum.map(& &1.bytes) |> Enum.sum()}
    end)
    |> Enum.sort_by(& &1.bytes, :desc)
  end

  # Raise at 70, critical at 90, and stay raised until below 60.
  defp level(_current, percent) when percent >= @critical, do: :critical
  defp level(_current, percent) when percent >= @caution, do: :caution
  defp level(nil, _percent), do: nil
  defp level(_current, percent) when percent < @clear, do: nil
  defp level(_current, _percent), do: :caution

  defp refusing(state, refusing?, now) do
    cond do
      refusing? and not state.refusing ->
        {%{state | refusing: true, refused_since: now}, true}

      not refusing? and state.refusing ->
        {%{
           state
           | refusing: false,
             refused_since: nil,
             refused_spell: {state.refused_since, now}
         }, true}

      true ->
        {state, false}
    end
  end

  defp resolve(state, now) do
    {from, to} = state.refused_spell || {nil, nil}
    entry = %{resolved_at: now, refused_from: from, refused_to: to}

    %{
      state
      | raised_at: nil,
        refused_spell: nil,
        resolved: [entry | resolved(state, now)]
    }
  end

  # Signed bytes per hour over the last hour's samples (newest first); nil with one sample.
  defp rate_per_hour([{newest_at, newest} | _] = samples) when length(samples) > 1 do
    {oldest_at, oldest} = List.last(samples)

    case DateTime.diff(newest_at, oldest_at, :millisecond) do
      ms when ms > 0 -> round((newest - oldest) * 3_600_000 / ms)
      _same -> nil
    end
  end

  defp rate_per_hour(_samples), do: nil

  # Only while growing: seconds until the disk is full at the current rate.
  defp eta_full_s(%{size_bytes: size, used_bytes: used}, rate)
       when is_integer(rate) and rate > 0,
       do: round(max(size - used, 0) * 3_600 / rate)

  defp eta_full_s(_reading, _rate), do: nil
end
