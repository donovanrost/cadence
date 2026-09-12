defmodule Cadence.Reads.Dashboards.Playlists do
  @moduledoc "Scoped playlist directory and published presentation snapshots."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards.{Authoring, AuthoringInput, Management, PlaylistInput, PlaylistStore}
  alias Cadence.Missions
  alias Cadence.Reads.Dashboards.Workspace

  def directory(scope, mission, params) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, query} <- PlaylistInput.query(params) do
      {:ok,
       Map.merge(identity(scope, mission), %{
         query: query,
         playlists: PlaylistStore.list(scope.organization_id, mission, query),
         choices: PlaylistStore.choices(scope.organization_id, mission, %{q: "", after: nil})
       })}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def search(scope, mission, params) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, query} <- PlaylistInput.query(params) do
      {:ok,
       Map.merge(identity(scope, mission), %{
         query: query,
         choices: PlaylistStore.choices(scope.organization_id, mission, query)
       })}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def present(scope, mission, id, params, opts \\ []) do
    with :ok <- authorize_view(scope, mission),
         true <- AuthoringInput.id?(id),
         {:ok, playlist} <- Management.fetch_playlist(scope.organization_id, mission, id),
         true <- PlaylistInput.ids?(playlist.dashboard_ids),
         total = length(playlist.dashboard_ids),
         {:ok, index, playing} <- PlaylistInput.position(params, total, playlist.wallboard_mode) do
      dashboard_id = Enum.at(playlist.dashboard_ids, index)
      metadata = PlaylistStore.dashboard(scope.organization_id, mission, dashboard_id)

      snapshot =
        case Workspace.load(scope, mission, dashboard_id, :view, opts) do
          {:ok, model} when not is_nil(metadata) -> model
          _ -> nil
        end

      {:ok,
       Map.merge(identity(scope, mission), %{
         playlist: %{
           id: id,
           name: playlist.name,
           description: playlist.description || "",
           dwell_seconds: playlist.dwell_seconds,
           wallboard_mode: playlist.wallboard_mode
         },
         index: index,
         total: total,
         playing: playing,
         loaded_at: DateTime.to_iso8601(DateTime.utc_now()),
         current: %{
           id: dashboard_id,
           name:
             if(snapshot, do: snapshot.name, else: if(metadata, do: metadata.name, else: nil)),
           snapshot: snapshot
         }
       })}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp identity(scope, mission),
    do: %{version: 1, organization_id: scope.organization_id, mission_id: mission}

  defp authorize_view(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission) do
    with true <- Enum.all?([scope.organization_id, mission, user], &AuthoringInput.id?/1),
         true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission),
         do: :ok
  end

  defp authorize_view(_, _), do: {:error, :unavailable}
end
