defmodule Cadence.Reads.PassEnders do
  @moduledoc """
  Who ended a booking, for the passes read (`ended_by`, qa #30), so the console says "Canceled
  by QA Org Admin" and blames the provider only when the provider ended it:

  - an operator's #53 "not booked" resolution → that user;
  - a cancel from the contact workspace (`contact_schedule_operations`) → that user;
  - otherwise the provider (`%{kind: "provider", id, name}`).

  Only canceled, rejected and failed rows have one.
  """

  import Ecto.Query

  alias Cadence.Contacts.ScheduleOperation
  alias Cadence.Control.ActorRef
  alias Cadence.Repo

  @ended [:canceled, :rejected, :failed]

  @doc """
  `%{reservation_id => actor}` for the user-ended bookings among `reservations`, and
  `%{{:resolution, reservation_id} => actor}` for their #53 resolutions.
  """
  @spec load(binary(), binary(), [struct()]) :: %{(binary() | {:resolution, binary()}) => map()}
  def load(organization_id, mission_id, reservations) do
    ended = Enum.filter(reservations, &(&1.lifecycle_state in @ended))
    cancels = cancels(organization_id, mission_id, Enum.map(ended, & &1.provider_reservation_id))

    resolutions =
      for r <- ended, %{} = doc <- [resolution_actor(r)], do: {r.provider_reservation_id, doc}

    named(organization_id, cancels, resolutions)
  end

  defp cancels(_organization_id, _mission_id, []), do: []

  defp cancels(organization_id, mission_id, ids) do
    ScheduleOperation
    |> where(
      [o],
      o.organization_id == ^organization_id and o.mission_id == ^mission_id and
        o.action == "cancel" and o.reservation_id in ^ids
    )
    |> select([o], {o.reservation_id, o.user_id})
    |> Repo.all()
  end

  # #146 (#468): a person is named, and keeps their id, only while an active member of the
  # mission's organization (one lookup per read, ActorRef); any other person reads id and name
  # nil, never by a stored name or an email an older resolution still holds.
  defp named(organization_id, cancels, resolutions) do
    names =
      ActorRef.names(
        organization_id,
        Enum.map(cancels, &elem(&1, 1)) ++ Enum.map(resolutions, &elem(&1, 1))
      )

    cancels
    |> Map.new(fn {reservation_id, actor_id} -> {reservation_id, canceller(actor_id, names)} end)
    |> Map.merge(
      Map.new(resolutions, fn {reservation_id, doc} ->
        {{:resolution, reservation_id}, ActorRef.document(doc, names)}
      end)
    )
  end

  defp resolution_actor(reservation) do
    case get_in(reservation.metadata || %{}, ["operator_resolution"]) do
      %{"action" => "not_booked", "actor" => %{} = actor} -> actor
      _none -> nil
    end
  end

  @doc "The row's `ended_by`, or nil for a booking that hasn't ended."
  @spec ended_by(struct(), %{binary() => map()}) :: map() | nil
  def ended_by(%{lifecycle_state: state} = reservation, enders) when state in @ended do
    resolution = get_in(reservation.metadata || %{}, ["operator_resolution"])

    cond do
      match?(%{"action" => "not_booked", "actor" => %{}}, resolution) ->
        Map.get(enders, {:resolution, reservation.provider_reservation_id})

      Map.has_key?(enders, reservation.provider_reservation_id) ->
        enders[reservation.provider_reservation_id]

      true ->
        %{
          kind: "provider",
          id: reservation.provider_id,
          name: get_in(reservation.metadata || %{}, ["provider_display_name"])
        }
    end
  end

  def ended_by(_reservation, _enders), do: nil

  # Through ActorRef.ref (api on #558), so a service that cancelled is named as a service.
  defp canceller(id, names) when is_binary(id), do: ActorRef.ref(id, names)
  defp canceller(_none, _names), do: %{kind: "user", id: nil, name: nil}
end
