defmodule CadenceWeb.Console.AttentionController do
  @moduledoc """
  Acknowledge and resolve a mission attention item (DECISIONS #54, ux U32).
  Contract: docs/apogee/api/contacts.md. The actor is always the signed-in user
  (DECISIONS #30/#32): a body naming an actor gets `actor_not_assignable`.
  """

  use CadenceWeb, :controller

  alias Cadence.Contacts.BookingResolutions.Attention, as: PassResolutions

  alias Cadence.Contacts.{
    ArchiveQuarantineAttention,
    ContactSettlementAttention,
    ContactStartAttention,
    IngressBackpressureAttention
  }

  alias Cadence.Reads.ActionQueue.AttentionItems
  alias CadenceWeb.Console.Problem

  @max_action_text 200
  @actor_keys ~w(actor actor_id actor_kind user_id resolved_by acknowledged_by by)

  # todo(authz): Cedar should decide who may acknowledge or resolve each attention source (any
  # mission operator today), e.g. only provider-account owners for pass resolutions.
  def acknowledge(conn, %{"source" => source, "id" => id} = params) do
    with :ok <- no_actor(params),
         {:ok, actions} <- source(source) do
      case actions.acknowledge(scope(conn), mission_id(conn), id) do
        {:error, :forbidden} when source == "contact_start" -> not_operator(conn)
        {:error, :forbidden} when source == "ingress_backpressure" -> not_operator(conn, :lost)
        result -> respond(conn, result)
      end
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

  # #71 replay stopped after 6 attempts: an operator starts it again (contact_settlement only).
  def retry(conn, %{"source" => "contact_settlement", "id" => id} = params) do
    case no_actor(params) do
      :ok ->
        respond_retry(conn, ContactSettlementAttention.retry(scope(conn), mission_id(conn), id))

      {:error, reason} ->
        problem(conn, reason)
    end
  end

  # DECISIONS #88 / ux U49: retry re-indexes quarantined archive entries synchronously and
  # answers with the counts; the item is resolved when nothing still fails.
  def retry(conn, %{"source" => "archive_quarantine", "id" => id} = params) do
    with :ok <- no_actor(params),
         {:ok, %{item: item, indexed: indexed, still_failing: still_failing}} <-
           ArchiveQuarantineAttention.retry(scope(conn), mission_id(conn), id) do
      names = AttentionItems.lookups(scope(conn).organization_id, mission_id(conn), [item])

      json(conn, %{
        data: %{
          item: AttentionItems.object(item, names),
          indexed: indexed,
          still_failing: still_failing
        }
      })
    else
      {:error, reason} -> problem(conn, reason)
    end
  end

  def retry(conn, _params), do: problem(conn, :attention_item_not_found)

  defp respond_retry(conn, {:error, {:retry_not_manual, item}}) do
    names = AttentionItems.lookups(scope(conn).organization_id, mission_id(conn))
    Problem.respond(conn, :retry_not_manual, %{"item" => AttentionItems.object(item, names)})
  end

  defp respond_retry(conn, result), do: respond(conn, result)

  # Sources with operator actions. contact_settlement: only a lost item can be acknowledged.
  defp source("pass_resolution"), do: {:ok, PassResolutions}
  defp source("contact_settlement"), do: {:ok, ContactSettlementAttention}
  # U45: only a missed pass can be marked as seen (acknowledge); there's nothing to resolve.
  defp source("contact_start"), do: {:ok, ContactStartAttention}

  # #83 / U47: only dropped frames (lost telemetry) are acknowledged; a filling buffer clears itself.
  defp source("ingress_backpressure"), do: {:ok, IngressBackpressureAttention}
  # #88: no acknowledge (attention_item_not_open); resolve discards, with the reason required.
  defp source("archive_quarantine"), do: {:ok, ArchiveQuarantineAttention}
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
    names = AttentionItems.lookups(scope(conn).organization_id, mission_id(conn), [item])
    json(conn, %{data: AttentionItems.object(item, names)})
  end

  defp respond(conn, {:error, reason}), do: problem(conn, reason)

  # ux U45: who may mark a missed pass as seen.
  defp not_operator(conn, what \\ :missed_pass) do
    conn
    |> put_status(:forbidden)
    |> json(Problem.body("forbidden", not_operator_message(what), nil))
  end

  defp not_operator_message(:missed_pass), do: "Operators mark missed passes as seen."
  defp not_operator_message(:lost), do: "Operators acknowledge lost telemetry."

  defp problem(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp problem(conn, {:invalid, %{action: message}}),
    do: Problem.respond(conn, :invalid_params, %{"action_text" => message})

  defp problem(conn, {:actor_not_assignable, keys}),
    do: Problem.respond(conn, :actor_not_assignable, %{"fields" => keys})

  defp problem(conn, :contact_start_not_missed),
    do: Problem.respond(conn, :contact_start_not_missed)

  defp problem(conn, reason)
       when reason in [
              :attention_item_not_found,
              :attention_item_not_open,
              :forbidden,
              :reason_required
            ],
       do: Problem.respond(conn, reason)

  # Anything else a source returns (a store error, say) is a 503, not a crash.
  defp problem(conn, _reason), do: Problem.respond(conn, :attention_unavailable)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
