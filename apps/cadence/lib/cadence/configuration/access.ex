defmodule Cadence.Configuration.Access do
  @moduledoc """
  Authorization for mission change sets.

  Capabilities map onto today's policy actions until Cedar replaces them (DECISIONS #2):
  `config.stage` = operate the mission, `config.apply` / `config.rollback` = request activation,
  `config.review` = approve activation (users only), `config.discard_any` = organization admin.
  """

  alias Cadence.Auth.Policy
  alias Cadence.Auth.Scope
  alias Cadence.Missions
  alias Cadence.Missions.Mission

  @type action :: :read | :stage | :apply | :review | :rollback | :discard_any

  @capabilities [
    {"config.stage", :stage},
    {"config.apply", :apply},
    {"config.review", :review},
    {"config.rollback", :rollback},
    {"config.discard_any", :discard_any}
  ]

  @spec authorize(Scope.t(), String.t(), action()) :: {:ok, Mission.t()} | {:error, term()}
  def authorize(%Scope{} = scope, mission_id, action) when is_binary(mission_id) do
    with {:ok, %Mission{} = mission} <- fetch_mission(scope, mission_id),
         :ok <- check(scope, mission, action) do
      {:ok, mission}
    end
  end

  def authorize(%Scope{}, _mission_id, _action), do: {:error, :mission_not_found}

  @spec allowed?(Scope.t(), Mission.t(), action()) :: boolean()
  def allowed?(%Scope{} = scope, %Mission{} = mission, action),
    do: check(scope, mission, action) == :ok

  @spec permissions(Scope.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def permissions(%Scope{} = scope, mission_id) do
    with {:ok, mission} <- authorize(scope, mission_id, :read) do
      {:ok, for({name, action} <- @capabilities, allowed?(scope, mission, action), do: name)}
    end
  end

  @doc """
  Durable actor document `%{"kind", "id", "name"}` for audit fields. A person's `name` is their
  display name or nil, never their email (#471, ca-security's P1 on #462). Reads name actors
  through `Configuration.ActorNames` by id, so the stored name is only a record of the time.
  """
  @spec actor(Scope.t()) :: map()
  def actor(%Scope{actor_kind: :user, user: user}),
    do: %{"kind" => "user", "id" => user.user_id, "name" => present(user.display_name)}

  def actor(%Scope{actor_kind: :service, service_identity: service}),
    do: %{
      "kind" => "service",
      "id" => service.service_identity_id,
      "name" => service.display_name
    }

  defp present(name) when is_binary(name) and name != "", do: name
  defp present(_none), do: nil

  @doc "Key identifying an actor for author comparisons."
  @spec actor_key(map()) :: String.t()
  def actor_key(%{"kind" => kind, "id" => id}), do: kind <> ":" <> id

  defp fetch_mission(%Scope{organization_id: organization_id}, mission_id)
       when is_binary(organization_id) do
    case Missions.fetch_mission(organization_id, mission_id) do
      {:ok, mission} -> {:ok, mission}
      {:error, _reason} -> {:error, :mission_not_found}
    end
  end

  defp fetch_mission(%Scope{}, _mission_id), do: {:error, :mission_not_found}

  defp check(scope, mission, :discard_any) do
    policy(scope, mission, :manage_mission)
  end

  defp check(scope, mission, action) when action in [:read, :stage],
    do: policy(scope, mission, :operate_mission)

  defp check(scope, mission, action) when action in [:apply, :rollback],
    do: policy(scope, mission, :request_activation)

  defp check(scope, mission, :review), do: policy(scope, mission, :approve_activation)

  defp policy(scope, mission, policy_action) do
    case Policy.authorize(scope, policy_action, %{
           organization_id: mission.organization_id,
           mission_id: mission.mission_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end
end
