defmodule Cadence.Reads.EventSentences do
  @moduledoc """
  Operator sentences for the event log (Timeline, Investigate B2; ux review
  2026-11-09-timeline #1 and #3). Each names what the event is about, and
  `subject` gives the console a link target (`%{kind, id, name}`):

  - "Flight telemetry source caught up to 10:23:54Z"
  - "Catalog rev 2 (QA-E2E re-import) registered by Mira K."
  - "Contact with EARENDIL-004 completed, 10:22:54–10:23:52Z"

  A watermark retreat is `caution` only when it means something for the
  operator (a replay or late data), and the sentence says so; otherwise it is
  `info`. Unknown kinds fall back to the sentence-case key plus the entity,
  never Title Case. Pure: `context` carries the name lookups.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.MissionEvents.Entry

  alias Cadence.Reads.{
    ConfigRevisionEvents,
    ContactEndingEvents,
    OffPlanBookingEvents,
    ScidMismatchEvents,
    WatermarkEvents,
    WindowMoveEvents
  }

  @type context :: %{
          spacecraft: %{optional(binary()) => {binary() | nil, integer() | nil}},
          users: %{optional(binary()) => binary()},
          dashboards: %{optional(binary()) => binary()},
          stations: %{optional(binary()) => map()}
        }

  @spec describe(Entry.t(), context()) :: %{
          text: binary(),
          subject: map() | nil,
          severity: atom() | nil
        }
  def describe(%Entry{} = entry, context) do
    kind = to_string(entry.kind || "")
    {text, subject, severity} = sentence(kind, entry, context)
    %{text: text, subject: subject, severity: severity}
  end

  defp sentence("source_watermark_advanced", entry, _ctx),
    do:
      {"#{source(entry)} caught up to #{time(current(entry)["complete_through"])}",
       source_ref(entry), nil}

  defp sentence("source_watermark_observed", entry, _ctx),
    do:
      {"#{source(entry)} has data through #{time(current(entry)["complete_through"])}",
       source_ref(entry), nil}

  # ux U60: the coalesced watermark events (WatermarkEvents); old per-write "advanced" rows above.
  defp sentence("source_watermark_settled", entry, ctx),
    do:
      {WatermarkEvents.settled(
         craft(entry, ctx),
         current(entry),
         payload(entry),
         entry.occurred_at
       ), contact_ref(entry), nil}

  defp sentence("source_watermark_caught_up", entry, ctx),
    do: {WatermarkEvents.caught_up(craft(entry, ctx), payload(entry)), source_ref(entry), nil}

  defp sentence("source_watermark_retreated", %Entry{spacecraft_id: id} = entry, ctx)
       when is_binary(id) do
    reason = retreat_reason(entry)
    text = WatermarkEvents.retreated(craft(entry, ctx), current(entry), reason == "data replay")
    {text, source_ref(entry), if(reason, do: :caution, else: :info)}
  end

  defp sentence("source_watermark_retreated", entry, _ctx) do
    base = "#{source(entry)} went back to #{time(current(entry)["complete_through"])}"

    case retreat_reason(entry) do
      nil -> {base, source_ref(entry), :info}
      reason -> {"#{base} (#{reason})", source_ref(entry), :caution}
    end
  end

  defp sentence("source_health_" <> change, entry, _ctx) do
    health = current(entry)["source_health"] || change

    text =
      if change == "recovered",
        do: "#{source(entry)} is healthy again",
        else: "#{source(entry)} is #{humanize(health)}"

    {text, source_ref(entry), nil}
  end

  defp sentence("scheduled_contact_interval", entry, ctx) do
    doc = current(entry)

    {"Contact #{doc["status"] || "scheduled"} for #{craft(entry, ctx)}, #{span(doc)}",
     contact_ref(entry), nil}
  end

  # U55/U56: who canceled or ended the contact and why (ContactEndingEvents).
  defp sentence(kind, entry, ctx)
       when kind in ["scheduled_contact_canceled", "realized_contact_ended_early"] do
    facts =
      ctx
      |> Map.get(:contacts, %{})
      |> Map.get(entry.scheduled_contact_id || entry.subject_id, %{})

    metadata = Map.merge(%{"reason" => entry.summary}, entry.metadata || %{})

    {ContactEndingEvents.sentence(kind, metadata, craft(entry, ctx), facts, by(entry, ctx)),
     contact_ref(entry), nil}
  end

  # Contacts read "Ended · not verified" until S9 checks the downlink: don't claim a flown pass.
  defp sentence("realized_contact_interval", entry, ctx) do
    doc = current(entry)

    {"Contact with #{craft(entry, ctx)} #{outcome(doc["status"])}, #{span(doc)}",
     contact_ref(entry), nil}
  end

  defp sentence("dashboard_" <> change, entry, ctx) do
    id = entry.subject_id
    name = Map.get(ctx.dashboards, id) || id
    version = payload(entry)["dashboard_version"]
    label = if version, do: "Dashboard #{name} v#{version}", else: "Dashboard #{name}"

    {"#{label} #{verb(change)}#{by(entry, ctx)}", %{kind: "dashboard", id: id, name: name}, nil}
  end

  defp sentence("catalog_revision_registered", entry, ctx) do
    doc = current(entry)
    label = if doc["revision_label"], do: " (#{doc["revision_label"]})", else: ""

    {"Catalog rev #{doc["revision_number"] || "?"}#{label} registered#{by(entry, ctx)}",
     %{kind: "catalog_revision", id: entry.subject_id, name: doc["revision_label"]}, nil}
  end

  defp sentence("config_revision_" <> _applied_or_rolled_back, entry, _ctx),
    do: {ConfigRevisionEvents.sentence(entry), ConfigRevisionEvents.subject(entry), nil}

  # Window truth (director 11-14; ux U56): the provider moved a booked pass; its contact followed.
  defp sentence("contact_window_moved", entry, ctx) do
    doc = Map.merge(current(entry), payload(entry))

    {WindowMoveEvents.sentence(doc, craft(entry, ctx), entry.occurred_at),
     %{kind: "pass", id: doc["provider_reservation_id"] || entry.subject_id, name: nil}, nil}
  end

  # ux U81 §2 (#102): most of a settled pass's frames carried another SCID. Caution; the
  # secondary line is the row's detail (`detail/2`).
  defp sentence("contact_scid_mismatch", entry, ctx) do
    doc = string_keys(payload(entry))

    {ScidMismatchEvents.title(doc, craft_name(entry, ctx), station(doc, ctx)), contact_ref(entry),
     :caution}
  end

  defp sentence("contact_booked_off_plan", entry, ctx),
    do:
      {OffPlanBookingEvents.sentence(entry, by(entry, ctx)),
       %{kind: "pass", id: entry.subject_id, name: nil}, nil}

  defp sentence("binding_set_activated", entry, ctx) do
    {"#{configuration(entry.summary)} activated#{by(entry, ctx)}",
     %{kind: "activation", id: entry.activation_id || entry.subject_id, name: nil}, nil}
  end

  defp sentence(kind, entry, ctx) do
    base =
      cond do
        is_binary(entry.title) and not title_case_key?(entry.title, kind) -> entry.title
        kind != "" -> humanize(kind)
        true -> entry.summary || "Event"
      end

    on = if entry.spacecraft_id, do: " on #{craft(entry, ctx)}", else: ""
    {base <> on, nil, nil}
  end

  defp retreat_reason(entry) do
    reason = to_string(payload(entry)["reason"] || "")

    cond do
      (entry.metadata || %{})["replay_run_id"] -> "data replay"
      String.contains?(reason, "replay") -> "data replay"
      String.contains?(reason, "late") -> "late data"
      true -> nil
    end
  end

  defp source(entry) do
    doc = payload(entry)
    realm = doc["data_realm"] || doc["dataset"]
    logical = doc["logical_source"]

    [realm, logical, "source"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.capitalize()
  end

  @doc "A row's secondary line, for the kinds that have one (nil otherwise)."
  @spec detail(Entry.t(), context()) :: binary() | nil
  def detail(%Entry{kind: kind} = entry, ctx)
      when kind in [:contact_scid_mismatch, "contact_scid_mismatch"],
      do: ScidMismatchEvents.detail(string_keys(payload(entry)), craft_name(entry, ctx))

  def detail(_entry, _ctx), do: nil

  # The spacecraft's name only (never its id), for words that drop the name when it's unknown.
  defp craft_name(%Entry{spacecraft_id: id}, ctx) do
    case Map.get(ctx.spacecraft, id) do
      {name, _scid} when is_binary(name) and name != "" -> name
      _unknown -> nil
    end
  end

  # A payload read back from the store has string keys; one projected in memory, atom keys.
  defp string_keys(%{} = map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp string_keys(_none), do: %{}

  defp station(doc, ctx) do
    case doc["ground_station_ref"] do
      ref when is_binary(ref) and ref != "" ->
        index = Map.get(ctx, :stations, %{})
        if Map.has_key?(index, ref), do: StationRefs.resolve(ref, index)

      _none ->
        nil
    end
  end

  defp source_ref(entry), do: %{kind: "data_source", id: entry.subject_id, name: source(entry)}

  defp contact_ref(entry),
    do: %{
      kind: "contact",
      id: entry.realized_contact_id || entry.scheduled_contact_id || entry.subject_id,
      name: nil
    }

  defp craft(%Entry{spacecraft_id: nil}, _ctx), do: "a spacecraft"

  defp craft(%Entry{spacecraft_id: id}, ctx) do
    case Map.get(ctx.spacecraft, id) do
      {name, _scid} when is_binary(name) -> name
      _unknown -> id
    end
  end

  # A person with no name here (not an active member of the organization, or no display name)
  # drops the clause: never their id (#472, ux U25). The entry keeps its actor, so its kind is
  # still at hand if ca-ux adds words later.
  defp by(%Entry{actor: actor}, ctx) do
    with id when is_binary(id) <- actor_id(actor),
         name when is_binary(name) <- Map.get(ctx.users, id) do
      " by #{name}"
    else
      _no_name -> ""
    end
  end

  @doc "The user id of an event actor, if a person acted."
  @spec actor_id(term()) :: binary() | nil
  def actor_id(actor) do
    actor = unwrap(actor)

    case actor do
      %{"kind" => "user", "id" => id} when is_binary(id) -> id
      %{kind: :user, id: id} when is_binary(id) -> id
      %{"kind" => "user", "user_id" => id} when is_binary(id) -> id
      _system -> nil
    end
  end

  # One Z for a range: 10:22:54–10:23:52Z.
  defp span(%{"starts_at" => from, "ends_at" => to}),
    do: "#{String.trim_trailing(time(from), "Z")}–#{time(to)}"

  defp span(_doc), do: "time unknown"

  defp outcome("completed"), do: "ended (not verified)"
  defp outcome(nil), do: "recorded"
  defp outcome(status), do: status |> to_string() |> String.replace("_", " ")

  defp time(nil), do: "an unknown time"

  defp time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _} ->
        at
        |> DateTime.truncate(:second)
        |> DateTime.to_time()
        |> Time.to_iso8601()
        |> Kernel.<>("Z")

      _bad ->
        iso
    end
  end

  # "Activated mission_applications:mission-earendil-demo v1" -> "Mission applications
  # configuration v1"; the internal key stays out of the sentence.
  defp configuration(summary) when is_binary(summary) do
    case Regex.run(~r/^Activated ([a-z_]+):\S+(?: (v\d+))?/, summary) do
      [_, area, version] -> "#{humanize(area)} configuration #{version}"
      [_, area] -> "#{humanize(area)} configuration"
      nil -> "Configuration"
    end
  end

  defp configuration(_summary), do: "Configuration"

  defp current(entry), do: unwrap((entry.metadata || %{})["current"]) || %{}
  defp payload(entry), do: unwrap((entry.metadata || %{})["payload"]) || %{}

  defp unwrap(%{"value" => value}), do: value
  defp unwrap(value), do: value

  defp verb(change), do: change |> to_string() |> String.replace("_", " ")

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  # The projection titles events by Title-Casing their key ("Source Watermark Advanced").
  defp title_case_key?(title, kind),
    do: String.downcase(title) == String.replace(kind, "_", " ")
end
