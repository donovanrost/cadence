defmodule CadenceWeb.Console.PassReservationController do
  @moduledoc """
  L14 / parity A11: `GET /passes/:id/reservation`, the pass's reservation links, provider
  values and paged audit (`?audit_cursor=`). Contract: docs/apogee/api/contacts.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.PassReservation
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"id" => id} = params) do
    case PassReservation.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           id,
           cursor(params["audit_cursor"])
         ) do
      {:ok, reservation} ->
        json(conn, %{data: ConfigJSON.encode(reservation)})

      {:error, :pass_not_found} ->
        Problem.respond(conn, :pass_not_found)

      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{audit_cursor: "is not a valid cursor"})
    end
  end

  defp cursor(value) when is_binary(value) and value != "", do: value
  defp cursor(_value), do: nil
end
