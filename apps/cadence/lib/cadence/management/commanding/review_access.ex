defmodule Cadence.Management.Commanding.ReviewAccess do
  @moduledoc "Fresh human authorization for command request review and decisions."
  alias Cadence.{Accounts, Ids, Missions}
  alias Cadence.Accounts.User
  alias Cadence.Auth.{Policy, Scope}

  def authorize(%Scope{actor_kind: :user, user: %{user_id: user_id}} = scope, mission_id) do
    with true <- is_binary(scope.organization_id) and scope.mission_id in [nil, mission_id],
         {:ok, _} <- Ids.path_segment(mission_id),
         {:ok, %User{lifecycle_state: :active} = user} <- Accounts.fetch_user(user_id),
         {:ok, membership} <- membership(scope, user),
         fresh =
           Scope.new(%{
             user: user,
             organization_id: scope.organization_id,
             organization_membership: membership,
             admin_mode?: scope.admin_mode?
           }),
         fresh = %{fresh | mission_id: scope.mission_id},
         :ok <-
           Policy.authorize(fresh, :manage_mission, %{
             organization_id: fresh.organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(fresh.organization_id, mission_id) do
      {:ok, fresh, mission}
    else
      _ -> {:error, :unavailable}
    end
  end

  def authorize(_, _), do: {:error, :unavailable}

  defp membership(scope, user) do
    case Accounts.fetch_user_membership(user.user_id, scope.organization_id) do
      {:ok, %{lifecycle_state: :active} = membership} ->
        {:ok, membership}

      _ ->
        if Scope.admin_mode?(Scope.new(%{user: user, admin_mode?: scope.admin_mode?})),
          do: {:ok, nil},
          else: {:error, :unavailable}
    end
  end
end
