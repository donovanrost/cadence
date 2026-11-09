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

  alias Cadence.MissionEvents.Entry

  @type context :: %{
          spacecraft: %{optional(binary()) => {binary() | nil, integer() | nil}},
          users: %{optional(binary()) => binary()},
          dashboards: %{optional(binary()) => binary()}
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

  defp sentence("scheduled_contact_canceled", entry, ctx) do
    why = if entry.summary == "provider_canceled", do: " by the provider", else: ""
    {"Contact for #{craft(entry, ctx)} canceled#{why}", contact_ref(entry), nil}
  end

  defp sentence("realized_contact_interval", entry, ctx) do
    doc = current(entry)

    {"Contact with #{craft(entry, ctx)} #{doc["status"] || "recorded"}, #{span(doc)}",
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

  defp sentence("binding_set_activated", entry, ctx) do
    {"Configuration activated#{by(entry, ctx)}#{detail(entry.summary)}",
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

  defp by(%Entry{actor: actor}, ctx) do
    case actor_id(actor) do
      nil -> ""
      id -> " by #{Map.get(ctx.users, id) || id}"
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

  defp span(%{"starts_at" => from, "ends_at" => to}), do: "#{time(from)}–#{time(to)}"
  defp span(_doc), do: "time unknown"

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

  defp detail(nil), do: ""
  defp detail(summary), do: ": " <> String.replace(summary, ~r/^Activated /, "")

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
