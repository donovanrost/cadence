defmodule CadenceWeb.Console.PassContactController do
  @moduledoc """
  U55: cancel a pass's contact before it's live, or end it while it is
  (`POST …/passes/:id/cancel-contact`, `…/end-contact`, `{reason}`). Neither touches the provider
  booking (that's Release). Operators only; the reason is recorded with the actor and the time.
  Answers with the pass row (GET /passes/:id). Contract: docs/apogee/api/contacts.md.
  Hand-started contacts aren't pass rows, so they're out of this step.
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.Contacts
  alias Cadence.Contacts.PassContacts
  alias Cadence.Reads.{PassContactFields, Passes}
  alias CadenceWeb.Console.{PassController, Problem}

  @max_reason 500

  def cancel(conn, %{"id" => id} = params), do: act(conn, id, params, "cancel")
  def finish(conn, %{"id" => id} = params), do: act(conn, id, params, "end")

  # todo(authz): Cedar should decide who may cancel or end a contact (any mission operator today).
  defp act(conn, id, params, wanted) do
    with :ok <- authorize(conn),
         {:ok, reason} <- reason(params["reason"]),
         {:ok, pass} <- pass(conn, id),
         {:ok, fact} <- fact(conn, pass),
         :ok <- allowed(fact, wanted),
         {:ok, _done} <- perform(conn, pass, fact, wanted, reason) do
      PassController.show(conn, %{"id" => id})
    else
      {:error, :forbidden} ->
        Problem.respond(conn, :forbidden)

      {:error, {:invalid_params, details}} ->
        Problem.respond(conn, :invalid_params, details)

      {:error, :pass_not_found} ->
        Problem.respond(conn, :pass_not_found)

      {:error, :no_scheduled_contact} ->
        Problem.respond(conn, :no_scheduled_contact)

      {:error, {code, state}} when code in [:contact_not_cancelable, :contact_not_live] ->
        Problem.respond(conn, code, %{state: state})

      {:error, _other} ->
        Problem.respond(conn, :contacts_unavailable)
    end
  end

  defp authorize(conn) do
    scope = conn.assigns.current_scope

    case Policy.authorize(scope, :operate_mission, %{
           organization_id: scope.organization_id,
           mission_id: mission_id(conn)
         }) do
      :ok -> :ok
      _denied -> {:error, :forbidden}
    end
  end

  defp reason(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:error, {:invalid_params, %{reason: "Give a reason first."}}}

      String.length(trimmed) > @max_reason ->
        {:error, {:invalid_params, %{reason: "Keep it under #{@max_reason} characters."}}}

      true ->
        {:ok, trimmed}
    end
  end

  defp reason(_text), do: {:error, {:invalid_params, %{reason: "Give a reason first."}}}

  defp pass(conn, id) do
    case Passes.fetch(org_id(conn), mission_id(conn), id) do
      {:ok, %{scheduled_contact_id: nil}} -> {:error, :no_scheduled_contact}
      {:ok, pass} -> {:ok, pass}
      {:error, :pass_not_found} -> {:error, :pass_not_found}
    end
  end

  defp fact(conn, pass) do
    case PassContacts.facts(org_id(conn), mission_id(conn), [pass.scheduled_contact_id]) do
      %{} = facts when map_size(facts) == 1 -> {:ok, facts[pass.scheduled_contact_id]}
      _missing -> {:error, :no_scheduled_contact}
    end
  end

  # The same rule the row's contact_action shows, so the button and the write agree.
  defp allowed(fact, wanted) do
    case PassContactFields.action(fact, DateTime.utc_now()) do
      ^wanted -> :ok
      "end" -> {:error, {:contact_not_cancelable, "active"}}
      "cancel" -> {:error, {:contact_not_live, "not_started"}}
      nil -> {:error, {refusal(wanted), ended_state(fact)}}
    end
  end

  defp refusal("cancel"), do: :contact_not_cancelable
  defp refusal("end"), do: :contact_not_live

  defp ended_state(%{state: :canceled}), do: "canceled"
  defp ended_state(%{ending: %{action_kind: :scheduled_contact_canceled}}), do: "canceled"
  defp ended_state(_fact), do: "ended"

  defp perform(conn, pass, _fact, "cancel", reason) do
    Contacts.cancel_scheduled_contact(org_id(conn), mission_id(conn), pass.scheduled_contact_id,
      reason: reason,
      actor: actor(conn),
      metadata: %{"cause" => "operator"}
    )
  end

  defp perform(conn, _pass, fact, "end", reason) do
    Contacts.end_realized_contact_early(org_id(conn), mission_id(conn), fact.realized_contact_id,
      reason: reason,
      actor: actor(conn),
      metadata: %{"cause" => "operator"}
    )
  end

  defp actor(conn) do
    user = conn.assigns.current_scope.user
    %{"kind" => "user", "id" => user.user_id, "name" => user.display_name}
  end

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
