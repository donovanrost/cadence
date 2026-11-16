defmodule CadenceWeb.Console.AlarmEpisodeController do
  @moduledoc """
  Alarm episodes for the console: list, show, acknowledge, assign, hand off
  and notes (DECISIONS #6, #17, #22). Contract: docs/apogee/api/alarms-console.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.Alarms
  alias Cadence.Reads.AlarmEpisodes
  alias CadenceWeb.Console.{AlarmEpisodeJSON, Problem}

  @states ~w(active cleared all)
  @severities ~w(critical caution)
  @sources ~w(catalog_monitoring ground_limit)
  @max_note 4_000

  def index(conn, params) do
    with {:ok, filters} <- filters(params),
         {:ok, list} <- AlarmEpisodes.list(scope(conn), mission_id(conn), filters),
         {:ok, permissions} <- Alarms.permissions(scope(conn), mission_id(conn)) do
      json(conn, %{
        data: AlarmEpisodeJSON.list(list, permissions),
        meta: %{next_cursor: list.next_cursor}
      })
    else
      {:error, {:invalid_params, details}} ->
        Problem.respond(conn, :invalid_params, details)

      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{cursor: "is not a valid cursor"})

      {:error, reason} ->
        problem(conn, reason)
    end
  end

  def show(conn, %{"episode_id" => episode_id}), do: respond_episode(conn, episode_id)

  def acknowledge(conn, %{"episode_id" => id} = params) do
    result =
      with {:ok, note} <- note(params, :optional) do
        run(conn, id, &Alarms.acknowledge(&1, &2, id, note))
      end

    finish(result, conn)
  end

  def assign(conn, %{"episode_id" => id} = params) do
    result =
      with {:ok, user_id} <- user_ref(params, "user_id"),
           {:ok, note} <- note(params, :optional) do
        run(conn, id, &Alarms.assign(&1, &2, id, user_id, note))
      end

    finish(result, conn)
  end

  def hand_off(conn, %{"episode_id" => id} = params) do
    result =
      with {:ok, to} <- user_ref(params, "to"),
           {:ok, note} <- note(params, :required) do
        run(conn, id, &Alarms.hand_off(&1, &2, id, %{to: to, note: note}))
      end

    finish(result, conn)
  end

  def add_note(conn, %{"episode_id" => id} = params) do
    result =
      with {:ok, note} <- note(params, :required) do
        run(conn, id, &Alarms.add_note(&1, &2, id, note))
      end

    finish(result, conn)
  end

  defp run(conn, episode_id, command) do
    case command.(scope(conn), mission_id(conn)) do
      {:ok, _episode} -> {:ok, respond_episode(conn, episode_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish({:ok, %Plug.Conn{} = conn}, _conn), do: conn

  defp finish({:error, {:invalid_params, details}}, conn),
    do: Problem.respond(conn, :invalid_params, details)

  defp finish({:error, reason}, conn), do: problem(conn, reason)

  defp respond_episode(conn, episode_id) do
    case AlarmEpisodes.get(scope(conn), mission_id(conn), episode_id) do
      {:ok, episode} -> json(conn, %{data: AlarmEpisodeJSON.episode(episode)})
      {:error, reason} -> problem(conn, reason)
    end
  end

  defp problem(conn, reason)
       when reason in [
              :episode_not_found,
              :episode_cleared,
              :note_required,
              :assignee_not_member,
              :forbidden
            ],
       do: Problem.respond(conn, reason)

  defp problem(conn, :mission_not_found), do: Problem.respond(conn, :mission_not_found)
  defp problem(conn, _reason), do: Problem.respond(conn, :alarms_unavailable)

  # -- params ------------------------------------------------------------------

  defp filters(params) do
    errors =
      %{}
      |> check(params, "state", @states)
      |> check(params, "severity", @severities)
      |> check(params, "source", @sources)

    errors =
      case limit(params["limit"]) do
        {:ok, _limit} -> errors
        :error -> Map.put(errors, "limit", "must be an integer from 1 to 200")
      end

    if errors == %{} do
      {:ok,
       %{
         state: params["state"] || "active",
         severity: params["severity"],
         source: params["source"],
         spacecraft_id: blank_to_nil(params["spacecraft_id"]),
         assignee_id: blank_to_nil(params["assignee_id"]),
         limit: elem(limit(params["limit"]), 1),
         # U69 A6d: a previous page's meta.next_cursor.
         cursor: blank_to_nil(params["cursor"])
       }}
    else
      {:error, {:invalid_params, errors}}
    end
  end

  defp check(errors, params, key, allowed) do
    value = Map.get(params, key)

    if is_nil(value) or value in allowed,
      do: errors,
      else: Map.put(errors, key, "must be one of #{Enum.join(allowed, ", ")}")
  end

  defp limit(nil), do: {:ok, 50}

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _other -> :error
    end
  end

  defp limit(_value), do: :error

  defp note(params, required) do
    case {Map.get(params, "note"), required} do
      {nil, :optional} ->
        {:ok, nil}

      {note, _} when is_binary(note) and byte_size(note) <= @max_note ->
        {:ok, blank_to_nil(String.trim(note))}

      {nil, :required} ->
        {:error, :note_required}

      _other ->
        {:error, {:invalid_params, %{"note" => "must be text up to #{@max_note} bytes"}}}
    end
  end

  # The key must be present: a user id, or null to unassign.
  defp user_ref(params, key) do
    case Map.fetch(params, key) do
      {:ok, nil} -> {:ok, nil}
      {:ok, id} when is_binary(id) and id != "" -> {:ok, id}
      _other -> {:error, {:invalid_params, %{key => "must be a user id or null"}}}
    end
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
