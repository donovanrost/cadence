defmodule Cadence.Dashboards.PlaylistAuthoring do
  @moduledoc "Authorized creation of an ordered playlist, independent of frontend delivery."
  alias Cadence.Dashboards.{Authoring, ConfigAudit, PlaylistInput, PlaylistStore}

  def create(scope, mission, input) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, fields} <- PlaylistInput.create(input),
         {:ok, playlist} <-
           PlaylistStore.create(scope.organization_id, mission, fields, scope.user.user_id) do
      audit(scope, mission, :playlist_created, playlist)

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

  @doc """
  Updates a playlist observed at `expected_updated_at` (the row's `updated_at`, to the
  microsecond; Q6). `{:ok, playlist}` or `{:error, :forbidden | :invalid_input | :not_found |
  {:invalid_dashboard, ids} | {:stale, current}}`. Audited.
  """
  def update(scope, mission, id, input, %DateTime{} = expected_updated_at) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, fields} <- PlaylistInput.update(input),
         {:ok, playlist} <-
           PlaylistStore.update(
             scope.organization_id,
             mission,
             id,
             fields,
             scope.user.user_id,
             expected_updated_at
           ) do
      audit(scope, mission, :playlist_updated, playlist)
      {:ok, playlist}
    else
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_input}
      {:error, _reason} = error -> error
    end
  end

  def update(_scope, _mission, _id, _input, _expected), do: {:error, :invalid_input}

  @doc "Deletes a playlist (hard; Q6). `:ok` or `{:error, :forbidden | :not_found}`. Audited."
  def delete(scope, mission, id) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, playlist} <- PlaylistStore.delete(scope.organization_id, mission, id) do
      audit(scope, mission, :playlist_deleted, playlist)
    end
  end

  defp audit(scope, mission, action, playlist),
    do:
      ConfigAudit.record(scope, mission, action, %{
        kind: "playlist",
        id: playlist.dashboard_playlist_id,
        label: playlist.name
      })
end
