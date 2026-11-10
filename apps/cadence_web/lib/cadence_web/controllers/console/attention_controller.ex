defmodule CadenceWeb.Console.AttentionController do
  @moduledoc """
  Acknowledge and resolve a mission attention item (DECISIONS #54, ux U32).
  Contract: docs/apogee/api/contacts.md. The actor is always the signed-in user
  (DECISIONS #30/#32): a body naming an actor gets `actor_not_assignable`.
  """

  use CadenceWeb, :controller

  alias Cadence.Contacts.BookingResolutions.Attention, as: PassResolutions
  alias Cadence.Reads.ActionQueue.AttentionItems
  alias CadenceWeb.Console.Problem

  @max_action_text 200
  @actor_keys ~w(actor actor_id actor_kind user_id resolved_by acknowledged_by by)

  # todo(authz): Cedar should decide who may acknowledge or resolve each attention source (any
  # mission operator today), e.g. only provider-account owners for pass resolutions.
  def acknowledge(conn, %{"source" => source, "id" => id} = params) do
    with :ok <- no_actor(params),
         {:ok, actions} <- source(source) do
      respond(conn, actions.acknowledge(scope(conn), mission_id(conn), id))
    else
      {:error, reason} -> problem(conn, reason)
    end
  end

  def resolve(conn, %{"source" => source, "id" => id} = params) do
    with :ok <- no_actor(params),
         {:ok, text} <- action_text(params["action_text"]),
         {:ok, actions} <- source(source) do
      respond(conn, actions.resolve(scope(conn), mission_id(conn), id, text))
    else
      {:error, reason} -> problem(conn, reason)
    end
  end

  # Only pass-resolution conflicts exist today; other sources join here.
  defp source("pass_resolution"), do: {:ok, PassResolutions}
  defp source(_unknown), do: {:error, :attention_item_not_found}

  defp no_actor(params) do
    case Enum.filter(@actor_keys, &Map.has_key?(params, &1)) do
      [] -> :ok
      keys -> {:error, {:actor_not_assignable, keys}}
    end
  end

  defp action_text(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> {:error, {:invalid_params, %{"action_text" => "is required"}}}
      String.length(trimmed) > @max_action_text -> {:error, {:invalid_params, too_long()}}
      true -> {:ok, trimmed}
    end
  end

  defp action_text(nil), do: {:error, {:invalid_params, %{"action_text" => "is required"}}}
  defp action_text(_other), do: {:error, {:invalid_params, %{"action_text" => "must be text"}}}

  defp too_long, do: %{"action_text" => "must be at most #{@max_action_text} characters"}

  defp respond(conn, {:ok, item}) do
    names = AttentionItems.lookups(conn.assigns.current_scope.organization_id, mission_id(conn))
    json(conn, %{data: AttentionItems.object(item, names)})
  end

  defp respond(conn, {:error, reason}), do: problem(conn, reason)

  defp problem(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp problem(conn, {:invalid, %{action: message}}),
    do: Problem.respond(conn, :invalid_params, %{"action_text" => message})

  defp problem(conn, {:actor_not_assignable, keys}),
    do: Problem.respond(conn, :actor_not_assignable, %{"fields" => keys})

  defp problem(conn, reason)
       when reason in [:attention_item_not_found, :attention_item_not_open, :forbidden],
       do: Problem.respond(conn, reason)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
