defmodule CadenceWeb.Console.ContactRecordController do
  @moduledoc """
  L14 / parity A13: `GET /contacts/:contact_id/record`, a scheduled or realized contact's record
  (both sides, paths with bindings, sources, intents, schedule history by `?revisions_cursor=`).
  Contract: docs/apogee/api/contacts.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.PassContactRecord
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"contact_id" => id} = params) do
    case PassContactRecord.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           id,
           cursor(params["revisions_cursor"])
         ) do
      {:ok, record} ->
        json(conn, %{data: ConfigJSON.encode(record)})

      {:error, :contact_not_found} ->
        Problem.respond(conn, :contact_not_found)

      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{revisions_cursor: "is not a valid cursor"})
    end
  end

  defp cursor(value) when is_binary(value) and value != "", do: value
  defp cursor(_value), do: nil
end
