defmodule Cadence.Reads.CommandReadAccess do
  @moduledoc "Mission operator authorization shared by command monitor and history reads."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions

  def authorize(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission) do
    with true <-
           Enum.all?([scope.organization_id, mission, user], &(query_text?(&1) and &1 != "")),
         true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission) do
      :ok
    else
      _ -> {:error, :unavailable}
    end
  end

  def authorize(_, _), do: {:error, :unavailable}

  defp query_text?(value),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) <= 256 and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, value)
end
