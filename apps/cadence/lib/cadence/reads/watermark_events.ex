defmodule Cadence.Reads.WatermarkEvents do
  @moduledoc """
  Timeline sentences for the coalesced watermark events (ux U60, domain storage-growth.md part
  2): the operational event fires on a change of state only, and every advance stays in the
  watermark table.

    * `source_watermark_settled`, once per contact at settle: "EARENDIL-008 · SVB 03:10Z pass:
      telemetry stored through 03:19:40Z (LOS 03:19:57Z)". Subject: the contact.
    * `source_watermark_caught_up`, after being ≥ 60 s behind: "Telemetry from EARENDIL-008
      caught up at 03:22Z after falling 2 min behind". Subject: the data source.
    * `source_watermark_retreated` with a spacecraft: "EARENDIL-008's stored telemetry moved
      back to 03:12Z" (+ " for a replay"). Without one, `EventSentences` keeps the source's own
      sentence.

  Where each field is read (domain d1c1ddd44): scope → `spacecraft_id`, `scheduled_contact_id`,
  `realized_contact_id`; current → `complete_through` (+ `reason`); payload → `ground_station_ref`,
  `starts_at`, `ends_at`, `behind_since`, `behind_max_seconds`, `caught_up_at`. Missing fields
  read as "unknown", never crash.
  """

  alias Cadence.Reads.WindowMoveEvents

  @spec settled(binary(), map(), map(), DateTime.t() | nil) :: binary()
  def settled(craft, current, payload, occurred_at) do
    pass =
      WindowMoveEvents.label(
        craft,
        payload["ground_station_ref"],
        payload["starts_at"],
        occurred_at
      )

    los =
      if parse(payload["ends_at"]), do: " (LOS #{clock(payload["ends_at"], :second)})", else: ""

    "#{pass}: telemetry stored through #{clock(current["complete_through"], :second)}#{los}"
  end

  @spec caught_up(binary(), map()) :: binary()
  def caught_up(craft, payload) do
    behind =
      case behind_seconds(payload) do
        nil -> ""
        seconds -> " after falling #{duration(seconds)} behind"
      end

    "Telemetry from #{craft} caught up at #{clock(payload["caught_up_at"], :minute)}#{behind}"
  end

  @spec retreated(binary(), map(), boolean()) :: binary()
  def retreated(craft, current, replay?) do
    "#{craft}'s stored telemetry moved back to #{clock(current["complete_through"], :minute)}" <>
      if(replay?, do: " for a replay", else: "")
  end

  defp behind_seconds(%{"behind_max_seconds" => seconds}) when is_number(seconds),
    do: round(seconds)

  defp behind_seconds(%{"behind_since" => since, "caught_up_at" => at}) do
    case {parse(since), parse(at)} do
      {%DateTime{} = since, %DateTime{} = at} -> DateTime.diff(at, since, :second)
      _unknown -> nil
    end
  end

  defp behind_seconds(_payload), do: nil

  # ux U60: "2 min", "90 s" under two minutes reads "1 min 30 s".
  defp duration(seconds) when seconds < 60, do: "#{seconds} s"

  defp duration(seconds) do
    case {div(seconds, 60), rem(seconds, 60)} do
      {minutes, 0} -> "#{minutes} min"
      {minutes, rest} when minutes < 2 -> "#{minutes} min #{rest} s"
      {minutes, _rest} -> "#{minutes} min"
    end
  end

  defp clock(value, precision) do
    case parse(value) do
      nil -> "an unknown time"
      at when precision == :minute -> Calendar.strftime(at, "%H:%MZ")
      at -> Calendar.strftime(at, "%H:%M:%SZ")
    end
  end

  defp parse(%DateTime{} = at), do: at

  defp parse(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp parse(_other), do: nil
end
