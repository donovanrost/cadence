defmodule Cadence.Commanding.Groups.ExpiredGroupAttention do
  @moduledoc """
  The `expired_group` source of the mission attention read (ux U75, DECISIONS #97): a command group
  whose deadline passed before all its members went out. One item per group (`id` = the group
  id), from its `expired` timeline event (`Groups.ExpiryEvent`), for 7 days or until an operator
  marks it as seen (`acknowledge/3`). Seen is recorded on that event's payload (`seen_at`,
  `seen_by`), so the group's log gets no extra line.

  P2. The queue row is `caution` when part of the group went out (`sent > 0`), `info` when none
  did. Keys: `group {id, title}`, `spacecraft_id` (the target when the group has one, else nil),
  `target_count`, `sent`, `total`, `expired_at`, `actions: ["acknowledge"]`.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Commanding.Groups.{CommandGroupEventRow, GroupStore}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @source "expired_group"
  @window_s 7 * 86_400

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    org
    |> events(mission)
    |> Enum.reject(&seen?/1)
    |> Enum.flat_map(&item(org, mission, &1))
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission),
    do: %{open: org |> events(mission) |> Enum.reject(&seen?/1) |> length(), acknowledged: 0}

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    for event <- events(org, mission),
        payload = payload(event),
        at = timestamp(payload["seen_at"]),
        at != nil and DateTime.compare(at, since) != :lt do
      %{
        id: event.command_group_id,
        source: @source,
        resolved_by: payload["seen_by"],
        action: "acknowledged",
        resolved_at: at
      }
    end
  end

  @doc "Marks an expired group as seen. Anything not open is `{:error, :attention_item_not_found}`."
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, group_id) do
    org = scope.organization_id
    now = DateTime.utc_now()

    with {:ok, actor} <- actor(scope, mission),
         %CommandGroupEventRow{} = event <- open_event(org, mission, group_id),
         seen =
           Map.merge(payload(event), %{"seen_at" => DateTime.to_iso8601(now), "seen_by" => actor}),
         {:ok, _row} <-
           event
           |> Ecto.Changeset.change(payload_document: JsonDocument.wrap_value(seen))
           |> Repo.update(),
         [item] <- item(org, mission, event) do
      ScopedReadUpdates.publish(:attention_changed, org, mission)

      {:ok,
       Map.merge(item, %{
         state: "resolved",
         acknowledged_by: actor,
         resolution: %{action: "acknowledged", actor: actor, at: now, note: nil}
       })}
    else
      {:error, reason} -> {:error, reason}
      _not_open -> {:error, :attention_item_not_found}
    end
  end

  @doc "Not an operator action for this source."
  @spec resolve(Scope.t(), binary(), binary(), String.t()) :: {:error, :attention_item_not_found}
  def resolve(_scope, _mission, _id, _text), do: {:error, :attention_item_not_found}

  @doc "Not an operator action for this source."
  @spec retry(Scope.t(), binary(), binary()) :: {:error, :attention_item_not_found}
  def retry(_scope, _mission, _id), do: {:error, :attention_item_not_found}

  defp events(org, mission) do
    since = DateTime.add(DateTime.utc_now(), -@window_s, :second)

    from(e in CommandGroupEventRow,
      where:
        e.organization_id == ^org and e.mission_id == ^mission and e.kind == "expired" and
          e.at >= ^since,
      order_by: [asc: e.at]
    )
    |> Repo.all()
  end

  defp open_event(org, mission, group_id) do
    org
    |> events(mission)
    |> Enum.find(&(&1.command_group_id == group_id and not seen?(&1)))
  end

  defp item(org, mission, event) do
    case GroupStore.fetch(org, mission, event.command_group_id) do
      {:ok, group} ->
        payload = payload(event)
        sent = payload["sent"] || 0
        targets = group.targets || []

        [
          %{
            id: group.command_group_id,
            source: @source,
            conflict: "expired",
            state: "open",
            severity: if(sent > 0, do: "caution", else: "info"),
            group: %{id: group.command_group_id, title: group.title},
            spacecraft_id: single_target(targets),
            target_count: length(targets),
            sent: sent,
            total: group.member_count,
            expired_at: event.at,
            raised_at: event.at,
            actions: ["acknowledge"],
            acknowledged_by: nil,
            resolution: nil
          }
        ]

      _gone ->
        []
    end
  end

  defp single_target([%{"spacecraft_id" => id}]), do: id
  defp single_target(_targets), do: nil

  defp seen?(event), do: Map.has_key?(payload(event), "seen_at")

  defp payload(event), do: JsonDocument.unwrap_value(event.payload_document || %{}) || %{}

  # todo(authz): Cedar should decide who may mark an expired group as seen (any operator today).
  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  defp timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp timestamp(_none), do: nil
end
