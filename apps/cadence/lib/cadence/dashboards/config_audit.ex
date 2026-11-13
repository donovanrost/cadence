defmodule Cadence.Dashboards.ConfigAudit do
  @moduledoc """
  Audit entries for dashboard configuration that isn't a dashboard document (DECISIONS #76 Q6/Q10,
  plans/dashboards-slice6.md and dashboards-library.md): playlists created, updated and deleted,
  library widgets retired, snapshots deleted. Each is a `dashboard_config_changed` operational
  event naming the actor and the target, read back as `config` lines of the organization audit
  ("Deleted playlist Ops wall", "Retired library widget Battery tile").
  """

  alias Cadence.Auth.Scope
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  @actions %{
    playlist_created: {"Created", "playlist"},
    playlist_updated: {"Updated", "playlist"},
    playlist_deleted: {"Deleted", "playlist"},
    library_item_retired: {"Retired", "library widget"},
    snapshot_deleted: {"Deleted", "snapshot of"}
  }

  @doc """
  Records `action` on `target` (`%{kind, id, label}`) by the scope's user. Runs inside the
  caller's transaction when there is one, so the entry and the change commit together.
  """
  @spec record(Scope.t(), binary(), atom(), map()) :: :ok
  def record(%Scope{} = scope, mission_id, action, %{kind: kind, id: id, label: label})
      when is_map_key(@actions, action) do
    now = DateTime.utc_now()
    entry = "#{action}:#{id}:#{DateTime.to_unix(now, :microsecond)}"

    {:ok, _event} =
      %{
        event_id: "operational_event:dashboard_config_change:#{entry}",
        organization_id: scope.organization_id,
        mission_id: mission_id,
        occurred_at: now,
        recorded_at: now,
        effective_at: now,
        category: :dashboard,
        kind: :dashboard_config_changed,
        severity: :info,
        actor: actor(scope),
        causality: %{source_record_kind: :dashboard_config_change, source_record_id: entry},
        payload: %{action: action, target_kind: kind, target_id: id, label: label}
      }
      |> Event.new()
      |> OperationalEvents.persist_event()

    :ok
  end

  @doc "A mission's entries, newest first, as organization audit `config` lines."
  @spec list(binary(), binary(), pos_integer()) :: [map()]
  def list(organization_id, mission_id, limit \\ 200) do
    organization_id
    |> OperationalEvents.list_events(mission_id, kind: [:dashboard_config_changed], limit: limit)
    |> Enum.flat_map(&line/1)
  end

  defp line(%Event{payload: payload} = event) do
    action = payload[:action] || payload["action"]
    label = payload[:label] || payload["label"]
    target_id = payload[:target_id] || payload["target_id"]
    target_kind = payload[:target_kind] || payload["target_kind"]

    case Map.get(@actions, to_atom(action)) do
      {verb, noun} ->
        [
          %{
            id: "config:dashboard_config:#{event.event_id}",
            at: event.occurred_at,
            actor: line_actor(event.actor),
            kind: "config",
            action: "#{verb} #{noun} #{label}",
            target: %{kind: to_string(target_kind), id: target_id, label: label},
            mission: nil,
            reason: nil
          }
        ]

      nil ->
        []
    end
  end

  defp to_atom(action) when is_atom(action), do: action

  defp to_atom(action) when is_binary(action) do
    Enum.find(Map.keys(@actions), &(Atom.to_string(&1) == action))
  end

  defp to_atom(_action), do: nil

  defp actor(%Scope{user: %{user_id: id} = user}),
    do: %{kind: :user, id: id, display_name: Map.get(user, :display_name)}

  defp actor(_scope), do: %{kind: :system}

  defp line_actor(%{kind: kind, id: id} = actor),
    do: %{kind: to_string(kind), id: id, name: Map.get(actor, :display_name)}

  defp line_actor(_actor), do: nil
end
