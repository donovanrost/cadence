defmodule Cadence.Dashboards.PlaylistAuthoring do
  @moduledoc "Authorized creation of an ordered playlist, independent of frontend delivery."
  alias Cadence.Dashboards.{Authoring, PlaylistInput, PlaylistStore}

  def create(scope, mission, input) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, fields} <- PlaylistInput.create(input),
         {:ok, playlist} <-
           PlaylistStore.create(scope.organization_id, mission, fields, scope.user.user_id) do
      {:ok,
       %{
         id: playlist.dashboard_playlist_id,
         name: playlist.name,
         count: length(playlist.dashboard_ids)
       }}
    else
      {:error, %Ecto.Changeset{}} ->
        {:error, :invalid_input}

      {:error, reason} when reason in [:invalid_input, :invalid_dashboard, :forbidden] ->
        {:error, reason}

      _ ->
        {:error, :unknown}
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end
end
