defmodule CadenceWeb.Console.ContactReleaseController do
  @moduledoc """
  U46 named release (DECISIONS #84): `POST /api/console/v1/missions/:mission_id/contacts/
  :realized_contact_id/release` sends armed command groups over a contact the operator names, a
  hand-started one included after ux's danger sheet (`confirm_unbooked: true`). Contract:
  docs/apogee/api/commanding.md §Named release.

  Each group goes through domain's `release_group_to_contact` in the order given, and later groups
  are still tried after one stops or is refused. A no about the contact itself (window closed, not
  a booked pass, not found, ended, no access) is the whole request's answer while nothing has
  gone out; after something has, it's a 200 and that group and the rest are refused with it.
  """

  use CadenceWeb, :controller

  alias Cadence.Contacts
  alias Cadence.Control.Commanding
  alias Cadence.Control.Commanding.GroupRelease
  alias CadenceWeb.Console.Problem

  @max_groups 50
  @contact_level ~w(command_window_closed unbooked_contact_unconfirmed realized_contact_not_found
                    realized_contact_not_releasable unavailable)a

  def release(conn, %{"realized_contact_id" => contact_id} = params) do
    with {:ok, group_ids} <- group_ids(params["command_group_ids"]),
         {:ok, confirm} <- confirm(params["confirm_unbooked"]) do
      results = release_all(conn, group_ids, contact_id, confirm)

      case whole_request_refusal(results) do
        nil -> json(conn, %{data: reply(conn, contact_id, results)})
        term -> refuse(conn, term)
      end
    else
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  defp release_all(conn, group_ids, contact_id, confirm) do
    group_ids
    |> Enum.reduce({[], nil}, fn
      id, {acc, nil} ->
        result =
          Commanding.release_group_to_contact(
            conn.assigns.current_scope,
            mission_id(conn),
            id,
            contact_id,
            confirm_unbooked: confirm
          )

        {[{id, result} | acc], contact_refusal(result)}

      # The contact said no: the rest get the same answer without being tried.
      id, {acc, refusal} ->
        {[{id, {:error, refusal}} | acc], refusal}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp contact_refusal({:error, term}) do
    if code(term) in @contact_level, do: term
  end

  defp contact_refusal(_ok), do: nil

  # The contact's own no is the whole answer while nothing has gone out.
  defp whole_request_refusal(results) do
    released? =
      Enum.any?(results, &match?({_id, {:ok, %{released_entry_ids: [_ | _]}}}, &1))

    refusal = Enum.find_value(results, fn {_id, result} -> contact_refusal(result) end)
    if refusal && not released?, do: refusal
  end

  defp refuse(conn, :unavailable), do: Problem.respond(conn, :forbidden)

  defp refuse(conn, term),
    do: Problem.respond(conn, code(term), encode(term, conn)["details"])

  defp reply(conn, contact_id, results) do
    %{
      realized_contact_id: contact_id,
      booked: booked?(conn, contact_id),
      results: Enum.map(results, &result(&1, conn))
    }
  end

  defp result({id, {:ok, released}}, conn) do
    %{
      command_group_id: id,
      outcome: if(released.stopped, do: "stopped", else: "released"),
      released_entry_ids: released.released_entry_ids,
      not_attempted_entry_ids: released.not_attempted_entry_ids,
      stopped: stopped(released.stopped, conn),
      refused: nil
    }
  end

  defp result({id, {:error, term}}, conn) do
    %{
      command_group_id: id,
      outcome: "refused",
      released_entry_ids: [],
      not_attempted_entry_ids: [],
      stopped: nil,
      refused: encode(term, conn)
    }
  end

  defp stopped(nil, _conn), do: nil

  defp stopped(stop, conn) do
    Map.merge(
      %{
        "command_queue_entry_id" => stop.command_queue_entry_id,
        "command_request_id" => stop.command_request_id
      },
      encode(stop.reason, conn)
    )
  end

  # Group-level refusals name what the console words; the rest are domain's encoding.
  defp encode({:command_group_not_armed, state}, _conn),
    do: reason("command_group_not_armed", %{"state" => to_string(state)})

  defp encode({:realized_contact_not_releasable, id, state}, _conn),
    do:
      reason("realized_contact_not_releasable", %{
        "realized_contact_id" => id,
        "state" => to_string(state)
      })

  defp encode({code, id}, _conn)
       when code in [
              :unbooked_contact_unconfirmed,
              :release_contact_not_target_spacecraft,
              :command_group_nothing_to_release,
              :realized_contact_not_found
            ] and is_binary(id),
       do: reason(Atom.to_string(code), %{"realized_contact_id" => id})

  defp encode(term, conn), do: GroupRelease.encode_reason(term, org_id(conn), mission_id(conn))

  defp reason(code, details), do: %{"code" => code, "details" => details}

  defp code(term) when is_atom(term), do: term
  defp code(term) when is_tuple(term) and is_atom(elem(term, 0)), do: elem(term, 0)
  defp code(_term), do: :unknown

  defp booked?(conn, contact_id) do
    case Contacts.fetch_realized_contact(org_id(conn), mission_id(conn), contact_id) do
      {:ok, contact} -> is_binary(contact.scheduled_contact_id)
      _gone -> false
    end
  end

  defp group_ids(ids) when is_list(ids) and ids != [] and length(ids) <= @max_groups do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")) and ids == Enum.uniq(ids),
      do: {:ok, ids},
      else: invalid_ids()
  end

  defp group_ids(_ids), do: invalid_ids()

  defp invalid_ids,
    do:
      {:error,
       %{
         command_group_ids: "Name 1 to #{@max_groups} different command groups, in release order."
       }}

  defp confirm(nil), do: {:ok, false}
  defp confirm(value) when is_boolean(value), do: {:ok, value}
  defp confirm(_value), do: {:error, %{confirm_unbooked: "Must be true or false."}}

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
