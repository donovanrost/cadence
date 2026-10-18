defmodule Cadence.Auth.SettingsAccess do
  @moduledoc "Authorizes settings actions against the current organization and optional mission."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions

  def authorize(%Scope{actor_kind: :user, user: %{user_id: id}} = scope, action, mission_id)
      when is_binary(id) and action in [:read_settings, :manage_settings] do
    with :ok <- bound_scope(scope, mission_id),
         :ok <-
           Policy.authorize(scope, action, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }) do
      mission_exists(scope.organization_id, mission_id)
    end
  end

  def authorize(_, _, _), do: {:error, :authenticated_user_required}

  def actor(scope),
    do: %{id: scope.user.user_id, name: scope.user.display_name || scope.user.email}

  defp mission_exists(_org, nil), do: :ok

  defp mission_exists(org, mission) do
    case Missions.fetch_mission(org, mission) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp bound_scope(%Scope{mission_id: nil}, _mission_id), do: :ok
  defp bound_scope(%Scope{mission_id: mission_id}, mission_id), do: :ok
  defp bound_scope(_, _), do: {:error, :scope_mismatch}
end
