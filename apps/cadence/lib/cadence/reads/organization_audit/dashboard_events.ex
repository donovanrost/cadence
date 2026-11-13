defmodule Cadence.Reads.OrganizationAudit.DashboardEvents do
  @moduledoc """
  Dashboard changes for the organization audit (`kind: "config"`, dashboards D3): created
  (version 1 made current), archived and restored, from the dashboard lifecycle events. Named by
  the dashboard's current name; the actor is whoever made the change.
  """

  alias Cadence.Dashboards.{Documents, LifecycleEvent}

  @types [:published, :archived, :restored]
  @limit 200

  @spec list(binary(), binary()) :: [map()]
  def list(organization_id, mission_id) do
    events =
      organization_id
      |> Documents.list_mission_lifecycle_events(mission_id, @types, @limit)
      |> Enum.filter(&shown?/1)

    names = names(organization_id, mission_id, events)
    Enum.map(events, &event(&1, names))
  end

  # Every save makes a version current; only the first (creation) is an audit line here.
  defp shown?(%LifecycleEvent{event_type: :published, dashboard_version: 1}), do: true
  defp shown?(%LifecycleEvent{event_type: :published}), do: false
  defp shown?(%LifecycleEvent{}), do: true

  defp event(%LifecycleEvent{} = event, names) do
    name = Map.get(names, event.dashboard_id) || event.dashboard_id

    %{
      id: "config:dashboard:#{event.dashboard_lifecycle_event_id}",
      at: event.occurred_at,
      actor: event.actor_id && %{kind: "user", id: event.actor_id, name: nil},
      kind: "config",
      action: "#{verb(event.event_type)} dashboard #{name}",
      target: %{kind: "dashboard", id: event.dashboard_id, label: name},
      mission: nil,
      reason: nil
    }
  end

  defp verb(:published), do: "Created"
  defp verb(:archived), do: "Archived"
  defp verb(:restored), do: "Restored"

  defp names(_organization_id, _mission_id, []), do: %{}

  defp names(organization_id, mission_id, _events) do
    (Documents.list_summaries(organization_id, mission_id) ++
       Documents.list_archived_summaries(organization_id, mission_id))
    |> Map.new(&{&1.dashboard_id, &1.name})
  end
end
