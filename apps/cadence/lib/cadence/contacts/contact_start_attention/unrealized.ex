defmodule Cadence.Contacts.ContactStartAttention.Unrealized do
  @moduledoc """
  `contact_start` items for scheduled passes that couldn't be realized (`RealizationFailure`; U45,
  lead 11-17 option A): no run exists, so the item is anchored on the booking. `id` is the
  scheduled contact id (a realized item's is its realized contact, `<scheduled>_run`, so they
  never collide) and `realized_contact_id` is null. Otherwise as a realized item: `not_started`
  while the window is open (the scheduler retries every reconcile), `missed` after, marked as seen
  by an operator; resolved `started` once realization succeeds.
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStartAttention.Passes
  alias Cadence.Contacts.{ContactStartFailure, ContactStore, ScheduledContact}
  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Repo

  @source "contact_start"

  @spec items(binary(), binary(), DateTime.t()) :: [map()]
  def items(org, mission, %DateTime{} = now) do
    contacts = open(org, mission)
    reservations = Passes.reservations(org, mission, contacts)
    Enum.map(contacts, &item(&1, Map.get(reservations, &1.scheduled_contact_id), now))
  end

  @spec count(binary(), binary()) :: non_neg_integer()
  def count(org, mission), do: length(open(org, mission))

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    for contact <- with_failure(org, mission),
        failure = contact.metadata["start_failure"],
        {action, at, by} <- resolution(failure),
        at != nil and DateTime.compare(at, since) != :lt do
      %{
        id: contact.scheduled_contact_id,
        source: @source,
        # The item's, as it was while open: null even once realized (fe-ops' 'Set up at').
        realized_contact_id: nil,
        resolved_by: by,
        action: action,
        resolved_at: at
      }
    end
  end

  @doc """
  Marks a missed unrealized pass as seen. `{:error, :attention_item_not_found}` when `id` names
  none open; `{:error, :contact_start_not_missed}` while its window is still open.
  """
  @spec acknowledge(binary(), binary(), binary(), map(), DateTime.t()) ::
          {:ok, map()} | {:error, term()}
  def acknowledge(org, mission, id, actor, %DateTime{} = now) do
    with {:ok, %ScheduledContact{} = contact} <- fetch_open(org, mission, id),
         reservation = Map.get(Passes.reservations(org, mission, [contact]), id),
         "missed" <- conflict(contact, reservation, now),
         failure =
           Map.merge(contact.metadata["start_failure"], %{
             "acknowledged_at" => DateTime.to_iso8601(now),
             "acknowledged_by" => actor
           }),
         {:ok, updated} <-
           ContactStore.update_scheduled_lifecycle(contact, contact.lifecycle_state, %{
             "start_failure" => failure
           }) do
      {:ok,
       updated
       |> item(reservation, now)
       |> Map.merge(%{
         state: "resolved",
         acknowledged_by: actor,
         resolution: %{action: "acknowledged", actor: actor, at: now, note: nil}
       })}
    else
      "not_started" -> {:error, :contact_start_not_missed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_open(org, mission, id) do
    case ContactStore.fetch_scheduled(org, mission, id) do
      {:ok, %ScheduledContact{} = contact} ->
        if open?(contact), do: {:ok, contact}, else: {:error, :attention_item_not_found}

      _other ->
        {:error, :attention_item_not_found}
    end
  end

  defp open(org, mission), do: org |> with_failure(mission) |> Enum.filter(&open?/1)

  defp open?(%ScheduledContact{} = contact) do
    case ContactStartFailure.open_failure(contact) do
      %{} = failure -> not Map.has_key?(failure, "acknowledged_at")
      nil -> false
    end
  end

  defp with_failure(org, mission) do
    from(row in ScheduledContactRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          fragment("? -> 'value' -> 'start_failure' IS NOT NULL", row.metadata)
    )
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  defp resolution(%{"realized_at" => at}),
    do: [{"started", Passes.timestamp(at), %{"kind" => "system"}}]

  defp resolution(%{"acknowledged_at" => at, "acknowledged_by" => by}),
    do: [{"acknowledged", Passes.timestamp(at), by}]

  defp resolution(_failure), do: []

  defp item(%ScheduledContact{} = contact, reservation, now) do
    failure = contact.metadata["start_failure"] || %{}

    %{
      id: contact.scheduled_contact_id,
      source: @source,
      conflict: conflict(contact, reservation, now),
      state: "open",
      reason: failure["reason"],
      failure_message: failure["failure_message"],
      contact_id: contact.scheduled_contact_id,
      realized_contact_id: nil,
      provider_profile_id: nil,
      provider_profile_name: nil,
      listen_port: failure["listen_port"],
      transport_id: failure["transport_id"],
      transport_name: failure["transport_name"],
      holder: nil,
      raised_at: Passes.timestamp(failure["first_failed_at"]),
      last_attempt_at: Passes.timestamp(failure["last_attempt_at"]),
      attempts: failure["attempts"] || 0,
      retry: "automatic",
      expires_at: nil,
      acknowledged_by: nil,
      resolution: nil
    }
    |> Map.merge(Passes.pass(reservation))
  end

  # The window comes from the booking, else the scheduled contact's own ends_at.
  defp conflict(%ScheduledContact{} = contact, reservation, now) do
    ends_at = (reservation && reservation.ends_at) || contact.ends_at
    if ends_at && DateTime.compare(ends_at, now) != :gt, do: "missed", else: "not_started"
  end
end
