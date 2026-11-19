defmodule Cadence.Control.Alarms do
  @moduledoc """
  Operator facade for the minimal alarm lifecycle (DECISIONS #6, #17): acknowledge, assign,
  hand off and note alarm episodes, plus episode reads. Episodes themselves are opened and
  auto-cleared in the data plane (`Cadence.Alarms.Episodes`). The console read with spacecraft
  and thresholds is `Cadence.Reads.AlarmEpisodes`. Design: `docs/apogee/domain/alarm-lifecycle.md`.

  Commands need a user who can operate the mission (exposed to the console as
  `alarm.acknowledge` / `alarm.assign`). Every command publishes `:alarms_changed` after commit.
  """

  alias Cadence.Accounts
  alias Cadence.Alarms.{History, Lifecycle, Notify, Queries}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions
  alias Cadence.Missions.Mission

  @spec list_episodes(Scope.t(), String.t(), Queries.filters()) ::
          {:ok, [map()]} | {:error, term()}
  def list_episodes(%Scope{} = scope, mission_id, filters \\ %{}) do
    with {:ok, mission} <- authorize(scope, mission_id, :read),
         do: {:ok, Queries.list(mission.mission_id, filters)}
  end

  @doc "U69 A6d: one page of episodes and the key after it (`Queries.page/2`)."
  @spec page_episodes(Scope.t(), String.t(), Queries.filters()) ::
          {:ok, %{episodes: [map()], next: term()}} | {:error, term()}
  def page_episodes(%Scope{} = scope, mission_id, filters \\ %{}) do
    with {:ok, mission} <- authorize(scope, mission_id, :read),
         do: {:ok, Queries.page(mission.mission_id, filters)}
  end

  @spec get_episode(Scope.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_episode(%Scope{} = scope, mission_id, episode_id) do
    with {:ok, mission} <- authorize(scope, mission_id, :read),
         do: Queries.get(mission.mission_id, episode_id)
  end

  @doc """
  A spacecraft's past episodes for Investigate's History tab (`Cadence.Alarms.History`):
  `%{stats, page}`, optionally for one point. `opts`: `point_id`, `before`, `limit`, `now`.
  """
  @spec spacecraft_history(Scope.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def spacecraft_history(%Scope{} = scope, mission_id, spacecraft_id, opts) do
    with {:ok, mission} <- authorize(scope, mission_id, :read) do
      filter = %{spacecraft_id: spacecraft_id, point_id: Map.get(opts, :point_id)}
      {:ok, history(mission.mission_id, filter, opts)}
    end
  end

  @doc """
  An episode with the same alarm's (`scope: :alarm`) or point's (`:point`) earlier episodes:
  `%{episode, stats, page}`. `opts` as `spacecraft_history/4`, plus `scope`.
  """
  @spec episode_history(Scope.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def episode_history(%Scope{} = scope, mission_id, episode_id, opts) do
    with {:ok, mission} <- authorize(scope, mission_id, :read),
         {:ok, episode} <- Queries.get(mission.mission_id, episode_id),
         {:ok, filter} <-
           History.filter_for(mission.mission_id, episode_id, Map.get(opts, :scope, :alarm)) do
      {:ok, Map.put(history(mission.mission_id, filter, opts), :episode, episode)}
    end
  end

  defp history(mission_id, filter, opts) do
    now = Map.get_lazy(opts, :now, &DateTime.utc_now/0)

    %{
      stats: History.stats(mission_id, filter, now),
      page:
        History.page(mission_id, filter, Map.get(opts, :before), Map.get(opts, :limit, 50), now)
    }
  end

  @spec summary(Scope.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def summary(%Scope{} = scope, mission_id) do
    with {:ok, mission} <- authorize(scope, mission_id, :read),
         do: {:ok, Queries.summary(mission.mission_id)}
  end

  @spec acknowledge(Scope.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission_id, episode_id, note \\ nil) do
    command(scope, mission_id, &Lifecycle.acknowledge(&1, episode_id, &2, note))
  end

  @doc "Assigns the episode to an organization member (`nil` unassigns). Doesn't acknowledge."
  @spec assign(Scope.t(), String.t(), String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def assign(%Scope{} = scope, mission_id, episode_id, user_id, note \\ nil) do
    with {:ok, mission} <- authorize(scope, mission_id, :act),
         {:ok, assignee} <- assignee(mission.organization_id, user_id) do
      command(scope, mission_id, &Lifecycle.assign(&1, episode_id, &2, assignee, note))
    end
  end

  @doc "Hands the episode to `to` (or leaves it unassigned for the next shift) with a required note."
  @spec hand_off(Scope.t(), String.t(), String.t(), %{to: String.t() | nil, note: String.t()}) ::
          {:ok, map()} | {:error, term()}
  def hand_off(%Scope{} = scope, mission_id, episode_id, %{note: note} = params) do
    with {:ok, mission} <- authorize(scope, mission_id, :act),
         {:ok, assignee} <- assignee(mission.organization_id, Map.get(params, :to)) do
      command(scope, mission_id, &Lifecycle.hand_off(&1, episode_id, &2, assignee, note))
    end
  end

  @spec add_note(Scope.t(), String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def add_note(%Scope{} = scope, mission_id, episode_id, note) do
    command(scope, mission_id, &Lifecycle.add_note(&1, episode_id, &2, note))
  end

  @doc "Console capabilities for alarm actions in this mission."
  @spec permissions(Scope.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def permissions(%Scope{} = scope, mission_id) do
    case authorize(scope, mission_id, :act) do
      {:ok, _mission} -> {:ok, ["alarm.acknowledge", "alarm.assign"]}
      {:error, :forbidden} -> {:ok, []}
      error -> error
    end
  end

  defp command(scope, mission_id, fun) do
    with {:ok, mission} <- authorize(scope, mission_id, :act),
         {:ok, episode} <- fun.(mission.mission_id, actor(scope)) do
      Notify.missions_changed([mission.mission_id])
      {:ok, Queries.view(episode)}
    end
  end

  defp authorize(%Scope{organization_id: organization_id} = scope, mission_id, action)
       when is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, %Mission{} = mission} <- fetch_mission(organization_id, mission_id),
         :ok <- human(scope, action),
         :ok <- operate(scope, mission) do
      {:ok, mission}
    end
  end

  defp authorize(%Scope{}, _mission_id, _action), do: {:error, :mission_not_found}

  defp fetch_mission(organization_id, mission_id) do
    case Missions.fetch_mission(organization_id, mission_id) do
      {:ok, mission} -> {:ok, mission}
      {:error, _reason} -> {:error, :mission_not_found}
    end
  end

  defp human(%Scope{actor_kind: :user}, :act), do: :ok
  defp human(%Scope{}, :act), do: {:error, :forbidden}
  defp human(%Scope{}, :read), do: :ok

  defp operate(scope, mission) do
    case Policy.authorize(scope, :operate_mission, %{
           organization_id: mission.organization_id,
           mission_id: mission.mission_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  defp assignee(_organization_id, nil), do: {:ok, nil}

  defp assignee(organization_id, user_id) when is_binary(user_id) do
    with {:ok, _membership} <- Accounts.fetch_user_membership(user_id, organization_id),
         {:ok, user} <- Accounts.fetch_user(user_id) do
      {:ok, %{"id" => user.user_id, "name" => user.display_name || user.email}}
    else
      _missing -> {:error, :assignee_not_member}
    end
  end

  defp assignee(_organization_id, _user_id), do: {:error, :assignee_not_member}

  defp actor(%Scope{user: user}),
    do: %{"kind" => "user", "id" => user.user_id, "name" => user.display_name || user.email}
end
