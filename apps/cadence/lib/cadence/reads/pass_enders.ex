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

  alias Cadence.Accounts.MemberNames
  alias Cadence.Contacts.ScheduleOperation
  alias Cadence.Repo

  @ended [:canceled, :rejected, :failed]

  @doc "`%{reservation_id => actor}` for the user-ended bookings among `reservations`."
  @spec load(binary(), binary(), [struct()]) :: %{binary() => map()}
  def load(organization_id, mission_id, reservations) do
    ids =
      for r <- reservations, r.lifecycle_state in @ended, do: r.provider_reservation_id

    if ids == [] do
      %{}
    else
      ScheduleOperation
      |> where(
        [o],
        o.organization_id == ^organization_id and o.mission_id == ^mission_id and
          o.action == "cancel" and o.reservation_id in ^ids
      )
      |> select([o], {o.reservation_id, o.user_id})
      |> Repo.all()
      |> named(organization_id)
    end
  end

  # #146 (#468): a person is named, and keeps their id, only while an active member of the
  # mission's organization (one lookup per read); any other person reads id and name nil, never
  # an email.
  defp named(enders, organization_id) do
    people = MemberNames.members(organization_id, Enum.map(enders, &elem(&1, 1)))
    Map.new(enders, fn {reservation_id, user_id} -> {reservation_id, user(user_id, people)} end)
  end

  @doc "The row's `ended_by`, or nil for a booking that hasn't ended."
  @spec ended_by(struct(), %{binary() => map()}) :: map() | nil
  def ended_by(%{lifecycle_state: state} = reservation, enders) when state in @ended do
    resolution = get_in(reservation.metadata || %{}, ["operator_resolution"])

    cond do
      match?(%{"action" => "not_booked", "actor" => %{}}, resolution) ->
        actor(resolution["actor"])

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

  defp actor(%{"kind" => kind} = actor),
    do: %{kind: kind, id: actor["id"], name: actor["name"]}

  defp actor(_actor), do: nil

  defp user(user_id, people) do
    case Map.fetch(people, user_id) do
      {:ok, name} -> %{kind: "user", id: user_id, name: name}
      :error -> %{kind: "user", id: nil, name: nil}
    end
  end
end
