defmodule CadenceWeb.Console.SingleBookingController do
  @moduledoc """
  §11 L15 single bookings (fe-ops' docs/apogee/plans/single-bookings.md; contract contacts.md
  §Book a pass): search one spacecraft's offers across its ready routes, and book one outside any
  plan. Release is the passes read's `POST /passes/:id/release` (the booker, else
  manage_missions). `Cadence.Contacts.SingleBookings` does the work; route keys and evidence stay
  inside the signed token.
  """

  use CadenceWeb, :controller

  alias Cadence.Accounts.MemberNames
  alias Cadence.Contacts.SingleBookings
  alias Cadence.Reads.Passes
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def search(conn, params) do
    case SingleBookings.search(scope(conn), mission_id(conn), Map.drop(params, ["mission_id"])) do
      {:ok, result} -> json(conn, %{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  # A16b: the route picker's options and the search limits.
  def routes(conn, params) do
    case SingleBookings.routes(scope(conn), mission_id(conn), params["spacecraft_id"]) do
      {:ok, result} -> json(conn, %{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  # Idempotent per booker and token: a retry returns the booking already asked for.
  def create(conn, params) do
    case SingleBookings.reserve(scope(conn), mission_id(conn), Map.take(params, ~w(token note))) do
      {:ok, booking} ->
        json(conn, %{data: ConfigJSON.encode(Map.put(booking, :pass, pass(conn, booking)))})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  # The /passes row (null when the provider rejected it), its booker named.
  defp pass(_conn, %{outcome: "rejected"}), do: nil

  defp pass(conn, %{reservation_id: id}) when is_binary(id) do
    case Passes.fetch(scope(conn).organization_id, mission_id(conn), id) do
      {:ok, %{off_plan: %{} = off_plan} = pass} ->
        %{
          pass
          | off_plan: named(off_plan, scope(conn).organization_id),
            releasable: pass.state in ~w(pending confirmed active)
        }

      {:ok, pass} ->
        pass

      _missing ->
        nil
    end
  end

  defp pass(_conn, _booking), do: nil

  # #146 (#468): the booker is named, and keeps their id, only as an active member of the
  # mission's organization (a platform admin acting in admin mode isn't); never by email.
  defp named(%{booked_by: %{id: id} = by} = off_plan, organization_id) when is_binary(id) do
    case MemberNames.members(organization_id, [id]) do
      %{^id => name} -> %{off_plan | booked_by: %{by | name: name}}
      _not_a_member -> %{off_plan | booked_by: %{by | id: nil, name: nil}}
    end
  end

  defp named(off_plan, _organization_id), do: off_plan

  defp error(conn, {:invalid, details}), do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, reason)
       when reason in [:route_changed, :opportunity_expired, :token_invalid, :search_unavailable],
       do: Problem.respond(conn, reason)

  defp error(conn, :not_found), do: Problem.respond(conn, :spacecraft_not_found)
  defp error(conn, _forbidden), do: Problem.respond(conn, :forbidden)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
