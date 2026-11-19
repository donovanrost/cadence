defmodule Cadence.ContactPlanning.BookingOutcomes do
  @moduledoc """
  Provider-side booking outcomes that arrive after a plan's execution finished, applied to the
  plan's execution items and re-projected onto the plan (`ContactPlanExecutions`):

  - `booking_settled/2`: an `uncertain` item (the provider hadn't answered when execution ended)
    takes its booking's outcome once the provider confirms, rejects or fails it, so the plan
    moves on to `reserved` / `partially_reserved` / `failed` without a re-execute.
  - `booking_lost/2`: a `reserved` item whose booking is canceled or failed provider-side fails
    with code `booking_lost` (qa #22), so repairs can re-plan the lost pass.
  """

  import Ecto.Query

  alias Cadence.ContactPlanning.ContactPlanExecutions
  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Control.Contacts.Store.ContactPlanExecutionItemRow
  alias Cadence.Repo

  @doc "Settles the `uncertain` items bound to `reservation` with its current outcome."
  @spec booking_settled(ProviderReservation.t(), keyword()) :: :ok | {:error, term()}
  def booking_settled(%ProviderReservation{} = reservation, opts \\ []) do
    reservation
    |> items_in("uncertain")
    |> each_projected(opts, &ContactPlanExecutions.finish_with_reservation(&1, reservation, opts))
  end

  @doc "Fails the `reserved` items bound to a booking the provider canceled or failed."
  @spec booking_lost(ProviderReservation.t(), keyword()) :: :ok | {:error, term()}
  def booking_lost(%ProviderReservation{} = reservation, opts \\ []) do
    error = %{
      "code" => "booking_lost",
      "provider_state" => Atom.to_string(reservation.lifecycle_state),
      "provider_reservation_id" => reservation.provider_reservation_id
    }

    reservation
    |> items_in("reserved")
    |> each_projected(
      opts,
      &ContactPlanExecutions.finish_item(
        &1,
        :failed,
        reservation.provider_reservation_id,
        error,
        opts
      )
    )
  end

  defp items_in(reservation, state) do
    ContactPlanExecutionItemRow
    |> where(
      [i],
      i.organization_id == ^reservation.organization_id and
        i.mission_id == ^reservation.mission_id and
        i.provider_reservation_id == ^reservation.provider_reservation_id and
        i.lifecycle_state == ^state
    )
    |> Repo.all()
    |> Enum.map(&ContactPlanExecutionItemRow.to_domain/1)
  end

  defp each_projected(items, opts, finish) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      with {:ok, item} <- finish.(item),
           {:ok, _plan, _items} <-
             ContactPlanExecutions.project_plan(
               item.organization_id,
               item.mission_id,
               item.contact_plan_id,
               item.contact_plan_version,
               opts
             ) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
