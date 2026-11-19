defmodule Cadence.Contacts.SingleBookings do
  @moduledoc """
  Single bookings: passes booked outside any plan (L15, DECISIONS #78). The console's Book a pass
  goes through here: `search/3` (`SingleBookings.Search`), `reserve/3`, `cancel/4`, over the
  shared, durable scheduling operations (`ScheduleOperations`, which make the provider call in a
  job and never repeat it).

  They're fixed occupancy: drafts and repairs plan around them (`occupancy/5`), never counting
  them toward a requirement, and a repair may pair one with a lost plan booking it covers (#56,
  `live/4`). The booker may cancel one; anything else needs `manage_missions`.

  Errors are a closed set for the console: `:route_changed`, `:opportunity_expired`,
  `:token_invalid`, `:search_unavailable`, `{:booking_changed, reservation}`, `:not_cancellable`,
  `:forbidden`, `:not_found`, `{:invalid, %{field => message}}`.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.{ProviderReservations, ScheduleCommands, ScheduleOperations}
  alias Cadence.Contacts.SingleBookings.{Occupancy, Routes, Search}
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  # How long reserve and cancel wait for the provider's first answer before saying "requested".
  @answer_wait_ms 3_000
  @poll_ms 200

  @doc """
  The permission cancelling a reservation needs (DECISIONS #78): the operator who booked a single
  booking may cancel it with `:operate_mission`; anything else needs `:manage_missions`.
  """
  # todo(authz): Cedar should decide who may cancel a booking (booker or mission manager today).
  @spec cancel_permission(binary(), binary(), binary() | nil, binary() | nil) ::
          :operate_mission | :manage_missions
  def cancel_permission(organization_id, mission_id, reservation_id, user_id)
      when is_binary(reservation_id) and is_binary(user_id) do
    booked_by =
      ProviderReservationRow
      |> where(
        [r],
        r.organization_id == ^organization_id and r.mission_id == ^mission_id and
          r.provider_reservation_id == ^reservation_id and is_nil(r.contact_plan_id)
      )
      |> select([r], fragment("? -> 'value' -> 'off_plan' -> 'booked_by' ->> 'id'", r.metadata))
      |> Repo.one()

    if booked_by == user_id, do: :operate_mission, else: :manage_missions
  end

  def cancel_permission(_organization_id, _mission_id, _reservation_id, _user_id),
    do: :manage_missions

  @doc "The reservation a cancel input names (`reservation_evidence.reservation_id`), or nil."
  def cancel_target(%{"reservation_evidence" => %{"reservation_id" => id}}) when is_binary(id),
    do: id

  def cancel_target(_input), do: nil

  @doc "Search one spacecraft's offers (`SingleBookings.Search.run/3`)."
  def search(%Scope{} = scope, mission, params), do: Search.run(scope, mission, params)

  @doc "A16b: the routes Book a pass can search for a spacecraft, with the search limits."
  @spec routes(Scope.t(), binary(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def routes(%Scope{} = scope, mission, spacecraft_id),
    do: Routes.list(scope, mission, spacecraft_id)

  @doc """
  Books the offer behind `token` (`%{"token", "note"}`; note at most 500 characters). Idempotent
  per booker and token. Waits up to #{@answer_wait_ms} ms for the provider's first answer:
  `{:ok, %{outcome: "confirmed" | "requested" | "unconfirmed" | "rejected", reason,
  reservation_id, provider_reference}}`.
  """
  def reserve(%Scope{} = scope, mission, %{"token" => token} = params) when is_binary(token) do
    input = %{"token" => token, "note" => params["note"]}

    id = operation_id(["reserve", scope.user.user_id, token])

    with :ok <- note(params["note"]),
         {:ok, operation} <- booked_or_request(scope, mission, id, input) do
      {:ok, outcome(scope, mission, await(scope, mission, operation))}
    end
  end

  def reserve(_scope, _mission, _params), do: {:error, {:invalid, %{"token" => "Search again"}}}

  @doc """
  Cancels a booking observed at `provider_revision`. `{:error, {:booking_changed, reservation}}`
  when it changed since; the booker, else `manage_missions` (DECISIONS #78).
  `{:ok, %{outcome: "canceled" | "requested", reservation_id}}`.
  """
  def cancel(%Scope{} = scope, mission, reservation_id, provider_revision) do
    org = scope.organization_id

    with {:ok, row} <- reservation(org, mission, reservation_id),
         :ok <- cancel_allowed(scope, mission, row),
         :ok <- same_revision(row, provider_revision),
         :ok <- cancellable(row),
         id = operation_id(["cancel", scope.user.user_id, reservation_id, provider_revision]),
         {:ok, %{status: status} = operation} when status != "not_accepted" <-
           ScheduleOperations.request(scope, mission, "cancel", request(id, evidence(row))) do
      operation = await(scope, mission, operation)
      canceled? = operation.status == "completed"

      {:ok,
       %{
         outcome: if(canceled?, do: "canceled", else: "requested"),
         reservation_id: reservation_id
       }}
    else
      {:ok, %{status: "not_accepted"}} ->
        {:error, {:booking_changed, current(org, mission, reservation_id)}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Live reservations overlapping `[from, to)` (`SingleBookings.Occupancy.list/5`)."
  defdelegate occupancy(organization_id, mission_id, from, to, opts \\ []),
    to: Occupancy,
    as: :list

  @doc "A planning run's fixed occupancy (`SingleBookings.Occupancy.document/3`)."
  defdelegate occupancy_document(organization_id, mission_id, attrs),
    to: Occupancy,
    as: :document

  @doc "The live booking a slot overlaps, or nil (`SingleBookings.Occupancy.overlap/2`)."
  defdelegate overlap(occupancy, slot), to: Occupancy

  @doc "Live single bookings overlapping `[from, to)` (`SingleBookings.Occupancy.live/4`)."
  defdelegate live(organization_id, mission_id, from, to), to: Occupancy

  ## Reserve and cancel steps

  defp note(nil), do: :ok

  defp note(note) when is_binary(note) do
    if String.length(note) <= 500,
      do: :ok,
      else: {:error, {:invalid, %{"note" => "Keep the note to 500 characters"}}}
  end

  defp note(_note), do: {:error, {:invalid, %{"note" => "Write the note as text"}}}

  # The same booker and token again: the booking already asked for, even once the token's route or
  # offer has moved on. Otherwise the token's checks, then a new operation.
  defp booked_or_request(scope, mission, id, input) do
    case ScheduleOperations.fetch(scope, mission, id) do
      {:ok, %{action: "reserve"} = operation} ->
        {:ok, operation}

      _new ->
        with {:ok, _reservation_id} <- precheck(scope, mission, input),
             do: request_reserve(scope, mission, id, input)
    end
  end

  defp request_reserve(scope, mission, id, input) do
    case ScheduleOperations.request(scope, mission, "reserve", request(id, input)) do
      {:ok, %{status: "not_accepted"}} -> {:error, :route_changed}
      other -> other
    end
  end

  # The token's checks before an operation is accepted, in the console's words.
  defp precheck(scope, mission, input) do
    case ScheduleCommands.reservation_identity(scope, mission, input) do
      {:ok, id} -> {:ok, id}
      {:error, reason} -> {:error, reserve_error(reason)}
    end
  end

  defp reserve_error(:route_changed), do: :route_changed
  defp reserve_error(:provider_scheduling_route_not_ready), do: :route_changed
  defp reserve_error(:opportunity_expired_or_unavailable), do: :opportunity_expired
  defp reserve_error(:expired_opportunity_capability), do: :opportunity_expired
  defp reserve_error(_invalid), do: :token_invalid

  defp request(id, payload),
    do: %{"contract_version" => 2, "operation_id" => id, "payload" => payload}

  # A UUID derived from the request, so a retry is the same operation (idempotent).
  defp operation_id(parts) do
    <<a::32, b::16, c::16, d::16, e::48, _rest::binary>> =
      :crypto.hash(:sha256, Enum.map_join(parts, "\u0000", &to_string/1))

    [a, b, c, d, e]
    |> Enum.zip([8, 4, 4, 4, 12])
    |> Enum.map_join("-", fn {n, w} ->
      n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(w, "0")
    end)
  end

  # Polls the operation until the provider answered, at most #{@answer_wait_ms} ms.
  defp await(scope, mission, operation, waited \\ 0)

  defp await(_scope, _mission, %{status: status} = operation, _waited)
       when status in ["completed", "rejected"],
       do: operation

  defp await(_scope, _mission, operation, waited) when waited >= @answer_wait_ms, do: operation

  defp await(scope, mission, operation, waited) do
    Process.sleep(@poll_ms)

    case ScheduleOperations.fetch(scope, mission, operation.operation_id) do
      {:ok, next} -> await(scope, mission, next, waited + @poll_ms)
      _gone -> operation
    end
  end

  defp outcome(scope, mission, %{reservation_id: id} = operation) do
    row = current(scope.organization_id, mission, id)
    state = row && row.lifecycle_state

    outcome =
      cond do
        state in [:confirmed, :active, :completed] -> "confirmed"
        state in [:rejected, :failed, :canceled] -> "rejected"
        operation.status == "rejected" -> "rejected"
        state == :unknown -> "unconfirmed"
        true -> "requested"
      end

    %{
      outcome: outcome,
      reason: if(outcome == "rejected", do: reason(row), else: nil),
      reservation_id: id,
      provider_reference: row && row.provider_contact_ref
    }
  end

  defp reason(nil), do: nil

  defp reason(row) do
    error = row.last_error_document || %{}
    get_in(error, ["reason", "category"]) || error["code"]
  end

  defp reservation(org, mission, id) when is_binary(id) do
    case ProviderReservations.fetch(org, mission, id) do
      {:ok, row} -> {:ok, row}
      _missing -> {:error, :not_found}
    end
  end

  defp reservation(_org, _mission, _id), do: {:error, :not_found}

  defp current(org, mission, id) do
    case ProviderReservations.fetch(org, mission, id) do
      {:ok, row} -> row
      _missing -> nil
    end
  end

  defp cancel_allowed(scope, mission, row) do
    permission =
      cancel_permission(
        scope.organization_id,
        mission,
        row.provider_reservation_id,
        scope.user.user_id
      )

    case Policy.authorize(scope, permission, %{
           organization_id: scope.organization_id,
           mission_id: mission
         }) do
      :ok -> :ok
      _denied -> {:error, :forbidden}
    end
  end

  defp same_revision(row, revision) do
    if row.provider_revision == revision, do: :ok, else: {:error, {:booking_changed, row}}
  end

  defp cancellable(%{lifecycle_state: state, provider_contact_ref: ref})
       when state in [:pending, :confirmed, :active] and is_binary(ref),
       do: :ok

  defp cancellable(_row), do: {:error, :not_cancellable}

  defp evidence(row),
    do: %{
      "reservation_evidence" => %{
        "contract_version" => 1,
        "organization_id" => row.organization_id,
        "mission_id" => row.mission_id,
        "reservation_id" => row.provider_reservation_id,
        "provider_revision" => row.provider_revision,
        "lifecycle_state" => Atom.to_string(row.lifecycle_state),
        "provider_contact_ref" => row.provider_contact_ref
      }
    }
end
