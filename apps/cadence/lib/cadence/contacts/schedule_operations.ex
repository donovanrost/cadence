defmodule Cadence.Contacts.ScheduleOperations do
  @moduledoc """
  Versioned contact scheduling application API shared by LiveVue and federation.

  Acceptance and job publication commit together. Jobs claim the intent before
  provider I/O; a restarted job only reconciles an already claimed intent. Neither
  a browser timeout nor a worker restart authorizes repeating a provider effect.
  """
  import Ecto.Query
  alias Cadence.{Accounts, Jobs, Repo}
  alias Cadence.Applications.JSONBoundary

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Contacts.{
    ProviderReservations,
    ScheduleCancellations,
    ScheduleCommands,
    ScheduleOperation
  }

  alias Cadence.Control.Contacts
  alias Cadence.Jobs.Available

  def request(
        scope,
        mission,
        action,
        %{"contract_version" => 2, "operation_id" => id, "observe" => true} = request
      )
      when map_size(request) == 3 and action in ["reserve", "cancel"] do
    case fetch(scope, mission, id) do
      {:ok, %{action: ^action} = operation} -> {:ok, %{operation: operation}}
      _ -> {:ok, %{operation: nil}}
    end
  end

  def request(scope, mission, "search", %{"contract_version" => 2, "payload" => input} = request)
      when map_size(request) == 2 do
    execute(scope, mission, "search", input)
  end

  def request(
        scope,
        mission,
        action,
        %{"contract_version" => 2, "operation_id" => id, "payload" => input} = request
      )
      when map_size(request) == 3 and action in ["reserve", "cancel"] do
    result =
      with :ok <- authorize(scope, mission, action),
           {:ok, ^id} <- Ecto.UUID.cast(id),
           {:ok, input} <- admit_input(input) do
        # Replay precedes capability expiry: accepted intents remain recoverable.
        case Repo.get(ScheduleOperation, id) do
          nil -> accept(scope, mission, action, id, input)
          row -> replay(row, scope, mission, action, input)
        end
      else
        _ -> {:error, :invalid_review}
      end

    case result do
      {:ok, operation} ->
        {:ok, operation}

      {:error, reason}
      when reason in [:operation_identity_collision, :reservation_operation_in_progress] ->
        {:ok,
         %{contract_version: 2, operation_id: id, status: "not_accepted", reason: "conflict"}}

      {:error, _} ->
        {:ok,
         %{
           contract_version: 2,
           operation_id: id,
           status: "not_accepted",
           reason: "review_changed"
         }}
    end
  end

  def request(_, _, _, _), do: {:error, :malformed_action_request}

  def page(scope, mission, page) do
    case authorize(scope, mission, "read") do
      :ok ->
        rows =
          Repo.all(
            from(r in scoped(scope, mission),
              order_by: [desc: r.inserted_at, desc: r.operation_id],
              offset: ^((page - 1) * 10),
              limit: 11
            )
          )

        %{
          contract_version: 2,
          actor_id: scope.user.user_id,
          operations: %{
            page: page,
            more: length(rows) > 10,
            entries: rows |> Enum.take(10) |> Enum.map(&projection(reconcile(&1)))
          }
        }

      _ ->
        nil
    end
  end

  def fetch(scope, mission, id) do
    with :ok <- authorize(scope, mission, "read"),
         {:ok, ^id} <- Ecto.UUID.cast(id),
         %ScheduleOperation{} = row <-
           Repo.one(from(r in scoped(scope, mission), where: r.operation_id == ^id)) do
      {:ok, projection(reconcile(row))}
    else
      _ -> {:error, :operation_not_found}
    end
  end

  def execute_enqueued_run(id) do
    case claim(id) do
      {:ok, {:claimed, row}} -> finish(row, perform(row))
      {:ok, {:existing, row}} -> {:ok, projection(reconcile(row))}
      {:error, _} = error -> error
    end
  end

  defp accept(scope, mission, action, id, input) do
    with {:ok, reservation} <- target(scope, mission, action, input),
         {:ok, {operation, job}} <-
           Repo.transaction(fn ->
             insert_intent(scope, mission, action, id, input, reservation)
           end) do
      # Dispatchers must see committed rows and must never join our transaction.
      if job, do: Available.publish(job)
      {:ok, operation}
    end
  end

  defp insert_intent(scope, mission, action, id, input, reservation) do
    now = DateTime.utc_now()

    attrs = %{
      operation_id: id,
      organization_id: scope.organization_id,
      user_id: scope.user.user_id,
      mission_id: mission,
      action: action,
      input: input,
      reservation_id: reservation,
      status: "accepted",
      revision: 1,
      admin_mode: Scope.admin_mode?(scope),
      inserted_at: now,
      updated_at: now
    }

    case Repo.insert_all(ScheduleOperation, [attrs], on_conflict: :nothing) do
      {1, _} -> enqueue(mission, id)
      {0, _} -> existing_intent(scope, mission, action, id, input)
    end
  end

  defp enqueue(mission, id) do
    case Jobs.enqueue_in_transaction(:contact_schedule_operation, mission, id, %{}) do
      {:ok, job} -> {projection(Repo.get!(ScheduleOperation, id)), job}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp existing_intent(scope, mission, action, id, input) do
    with %ScheduleOperation{} = row <- Repo.get(ScheduleOperation, id),
         {:ok, operation} <- replay(row, scope, mission, action, input) do
      {operation, nil}
    else
      nil -> Repo.rollback(:reservation_operation_in_progress)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp replay(row, scope, mission, action, input) do
    if row.organization_id == scope.organization_id and row.user_id == scope.user.user_id and
         row.mission_id == mission and row.action == action and row.input == input,
       do: {:ok, projection(reconcile(row))},
       else: {:error, :operation_identity_collision}
  end

  defp target(scope, mission, "reserve", input),
    do: ScheduleCommands.reservation_identity(scope, mission, input)

  defp target(scope, mission, "cancel", input) do
    with {:ok, evidence} <- ScheduleCancellations.admit(scope, mission, input),
         {:ok, _} <-
           ProviderReservations.fetch(scope.organization_id, mission, evidence["reservation_id"]),
         do: {:ok, evidence["reservation_id"]}
  end

  defp claim(id) do
    Repo.transaction(fn ->
      case Repo.one(
             from(r in ScheduleOperation, where: r.operation_id == ^id, lock: "FOR UPDATE")
           ) do
        nil -> Repo.rollback(:operation_not_found)
        %{status: "accepted"} = row -> {:claimed, transition(row, "unconfirmed", nil)}
        row -> {:existing, row}
      end
    end)
  end

  defp perform(row) do
    with {:ok, scope} <- current_scope(row),
         :ok <- authorize(scope, row.mission_id, row.action) do
      execute(scope, row.mission_id, row.action, row.input)
    else
      _ -> {:error, :forbidden}
    end
  rescue
    _ -> {:error, :unconfirmed}
  catch
    _, _ -> {:error, :unconfirmed}
  end

  defp execute(scope, mission, action, input),
    do: ScheduleCommands.execute(scope, mission, action, input)

  defp admit_input(%{"token" => token} = input) when map_size(input) == 1 do
    if is_binary(token) and byte_size(token) in 1..8_192 and String.valid?(token),
      do: {:ok, input},
      else: {:error, :invalid_input}
  end

  defp admit_input(input), do: JSONBoundary.safe(input)

  defp finish(row, result) do
    Repo.transaction(fn ->
      current =
        Repo.one!(
          from(r in ScheduleOperation,
            where: r.operation_id == ^row.operation_id,
            lock: "FOR UPDATE"
          )
        )

      if current.status == "unconfirmed" do
        {status, value} = outcome(result, row.action)
        current |> transition(status, value) |> reconcile() |> projection()
      else
        projection(current)
      end
    end)
  end

  defp outcome({:ok, value}, action) do
    if settled?(action, value["lifecycleState"]),
      do: {"completed", value},
      else: {"unconfirmed", value}
  end

  defp outcome({:error, reason}, _)
       when reason in [
              :forbidden,
              :scope_mismatch,
              :malformed_input,
              :malformed_action_request,
              :invalid_reservation_cancellation_evidence,
              :stale_reservation_cancellation_evidence,
              :provider_reservation_not_found,
              :opportunity_expired_or_unavailable,
              :invalid_opportunity_capability,
              :opportunity_scope_mismatch,
              :route_changed,
              :provider_scheduling_route_not_ready
            ],
       do: {"rejected", nil}

  defp outcome(_, _), do: {"unconfirmed", nil}

  # Recovery uses the identity sealed before dispatch. It never sends provider traffic.
  defp reconcile(%{status: "unconfirmed"} = row) do
    # A running worker still owns the decision. Observations must not race its
    # authorization/stale-review rejection into a spurious completion.
    case Jobs.fetch_job_for_run(:contact_schedule_operation, row.operation_id) do
      {:ok, %{status: :running}} -> row
      _ -> reconcile_reservation(row)
    end
  end

  defp reconcile(row), do: row

  defp reconcile_reservation(row) do
    case ProviderReservations.fetch(row.organization_id, row.mission_id, row.reservation_id) do
      {:ok, reservation} -> observe_reservation(row, booking(reservation))
      _ -> row
    end
  end

  defp observe_reservation(row, value) do
    status =
      if settled?(row.action, value["lifecycleState"]), do: "completed", else: "unconfirmed"

    if row.result != value or row.status != status do
      {_, rows} =
        Repo.update_all(
          from(r in ScheduleOperation,
            where:
              r.operation_id == ^row.operation_id and r.revision == ^row.revision and
                r.status == "unconfirmed",
            select: r
          ),
          set: [status: status, result: value, updated_at: DateTime.utc_now()],
          inc: [revision: 1]
        )

      List.first(rows) || Repo.get!(ScheduleOperation, row.operation_id)
    else
      row
    end
  end

  defp settled?("cancel", state), do: state == "canceled"

  defp settled?("reserve", state),
    do: state in ~w(pending confirmed active completed rejected canceled)

  defp booking(row) do
    scheduled =
      case Contacts.fetch_scheduled_contact(
             row.organization_id,
             row.mission_id,
             row.scheduled_contact_id
           ) do
        {:ok, contact} -> contact.scheduled_contact_id
        _ -> nil
      end

    %{
      "providerReservationId" => row.provider_reservation_id,
      "providerRevision" => row.provider_revision,
      "lifecycleState" => to_string(row.lifecycle_state),
      "scheduledContactId" => scheduled
    }
  end

  defp transition(row, status, result),
    do:
      row
      |> Ecto.Changeset.change(status: status, result: result, revision: row.revision + 1)
      |> Repo.update!()

  defp current_scope(row) do
    with {:ok, %{lifecycle_state: :active} = user} <- Accounts.fetch_user(row.user_id) do
      membership =
        case Accounts.fetch_user_membership(row.user_id, row.organization_id) do
          {:ok, member} -> member
          _ -> nil
        end

      {:ok,
       Scope.new(%{
         user: user,
         organization_id: row.organization_id,
         organization_membership: membership,
         admin_mode?: row.admin_mode
       })}
    end
  end

  defp authorize(%Scope{user: %{lifecycle_state: :active}} = scope, mission, action) do
    permission = if action == "cancel", do: :manage_missions, else: :operate_mission

    if scope.mission_id in [nil, mission],
      do:
        Policy.authorize(scope, permission, %{
          organization_id: scope.organization_id,
          mission_id: mission
        }),
      else: {:error, :forbidden}
  end

  defp authorize(_, _, _), do: {:error, :forbidden}

  defp scoped(scope, mission),
    do:
      from(r in ScheduleOperation,
        where:
          r.organization_id == ^scope.organization_id and r.user_id == ^scope.user.user_id and
            r.mission_id == ^mission
      )

  defp projection(row),
    do: %{
      contract_version: 2,
      operation_id: row.operation_id,
      actor_id: row.user_id,
      context: %{organization_id: row.organization_id, mission_id: row.mission_id},
      action: row.action,
      reservation_id: row.reservation_id,
      status: row.status,
      revision: row.revision,
      result: row.result
    }
end
