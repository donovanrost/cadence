defmodule Cadence.Reads.Dashboards.Activity do
  @moduledoc "Authorized, bounded dashboard version and lifecycle history without presentation or raw audit payloads."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards.{AuthoringInput, Documents}
  alias Cadence.Missions
  @max_version 9_007_199_254_740_990

  def load(scope, mission, dashboard, params \\ %{}) do
    with {:ok, author} <- authorize(scope, mission, dashboard),
         {:ok, query} <- admit(params),
         {:ok, _} <- Documents.fetch(scope.organization_id, mission, dashboard),
         {:ok, history} <- Documents.history(scope.organization_id, mission, dashboard, query) do
      {:ok, project(scope.organization_id, mission, dashboard, history, query, author)}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def admit(params) when is_map(params) do
    with true <-
           Map.keys(params) -- ~w(version before_version before_event selected_publish_issue) ==
             [],
         {:ok, version} <- number(params["version"]),
         {:ok, before_version} <- number(params["before_version"]),
         true <- optional_id?(params["before_event"]),
         true <- optional_id?(params["selected_publish_issue"]) do
      {:ok,
       %{
         version: version,
         before_version: before_version,
         before_event: params["before_event"],
         issue_id: params["selected_publish_issue"]
       }}
    else
      _ -> {:error, :invalid_input}
    end
  end

  def admit(_), do: {:error, :invalid_input}

  defp authorize(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission, dashboard) do
    resource = %{organization_id: scope.organization_id, mission_id: mission}

    with true <-
           Enum.all?([scope.organization_id, user, mission, dashboard], &AuthoringInput.id?/1),
         true <- scope.mission_id in [nil, mission],
         :ok <- Policy.authorize(scope, :operate_mission, resource),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission) do
      {:ok, Policy.authorize(scope, :author_dashboards, resource) == :ok}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp authorize(_, _, _), do: {:error, :unavailable}

  defp number(nil), do: {:ok, nil}

  defp number(value) when is_binary(value) and byte_size(value) <= 16 do
    case Integer.parse(value) do
      {n, ""} when n in 1..@max_version -> if(to_string(n) == value, do: {:ok, n}, else: :error)
      _ -> :error
    end
  end

  defp number(_), do: :error
  defp optional_id?(nil), do: true
  defp optional_id?(value), do: AuthoringInput.id?(value)

  defp project(org, mission, dashboard, history, query, author) do
    selected = history.selected

    %{
      version: 1,
      organization_id: org,
      mission_id: mission,
      dashboard_id: dashboard,
      name: history.dashboard.name,
      document_version: history.dashboard.latest_version,
      revision: history.dashboard.lock_version,
      published_version: history.dashboard.published_version,
      archived: history.dashboard.lifecycle_state == "archived",
      author: author,
      query: query,
      versions: Enum.map(history.versions, &version/1),
      next_version: history.next_version,
      selected:
        Map.merge(version(selected), %{
          name: selected.document.name,
          widget_count: length(selected.document.placements),
          section_count: length(selected.document.sections)
        }),
      events:
        Enum.map(history.events, fn event ->
          %{
            id: event.dashboard_lifecycle_event_id,
            event_type: event.event_type,
            document_version: event.dashboard_version,
            actor_id: event.actor_id,
            occurred_at: timestamp(event.occurred_at)
          }
        end),
      next_event: history.next_event
    }
  end

  defp version(value),
    do: %{
      version: value.version,
      kind: to_string(value.snapshot_kind),
      parent_version: value.parent_version,
      based_on_version: value.based_on_version,
      schema_version: value.schema_version,
      summary: value.change_summary || "",
      actor_id: value.created_by,
      saved_at: timestamp(value.inserted_at)
    }

  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
