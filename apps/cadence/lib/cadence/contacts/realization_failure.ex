defmodule Cadence.Contacts.RealizationFailure do
  @moduledoc """
  A scheduled pass that couldn't be REALIZED: Cadence refused to build its run (its paths didn't
  resolve, e.g. a pinned provider profile whose transport was archived), so no realized contact
  exists and nothing could record a start failure. Until 11-17 that was only a count in the
  scheduler's reconcile summary: a lost pass with no trace (U45; lead's option A).

  The failure is kept on the SCHEDULED contact's metadata as `start_failure`, in
  `ContactStartFailure`'s format, so the `contact_start` item shows it anchored on the booking
  (`realized_contact_id` null) while the scheduler retries every reconcile. It resolves
  (`realized_at`) once realization succeeds; if that run then fails to start, the realized
  contact's own item takes over. The first attempt is also logged, for whoever reads the logs.
  """

  require Logger

  alias Cadence.Contacts.{ContactStartFailure, ContactStore, ScheduledContact}
  alias Cadence.Platform.ScopedReadUpdates

  @doc """
  After the reconcile's realization of `contact` returned `error`: record it on the scheduled
  contact, unless a run was persisted after all (its start failed, which the realized contact
  records), in which case the realization failure resolves.
  """
  @spec after_error(ScheduledContact.t(), term(), DateTime.t()) :: :ok | {:error, term()}
  def after_error(%ScheduledContact{} = contact, error, %DateTime{} = at) do
    case ContactStore.fetch_scheduled(contact.mission_id, contact.scheduled_contact_id) do
      {:ok, %ScheduledContact{realized_contact_id: id} = current} when is_binary(id) ->
        realized(current, at)

      {:ok, %ScheduledContact{} = current} ->
        record(current, error, at)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Records a failed realization attempt on the scheduled contact and tells the Now queue."
  @spec record(ScheduledContact.t(), term(), DateTime.t()) :: :ok | {:error, term()}
  def record(%ScheduledContact{} = contact, error, %DateTime{} = at) do
    patch = ContactStartFailure.failed(contact, error, at)

    with {:ok, updated} <-
           ContactStore.update_scheduled_lifecycle(contact, contact.lifecycle_state, patch) do
      log_first(updated, error)
      announce(updated)
    end
  end

  @doc "The pass got past realization: its open realization failure resolves. `:ok` if none."
  @spec realized(ScheduledContact.t(), DateTime.t()) :: :ok | {:error, term()}
  def realized(%ScheduledContact{} = contact, %DateTime{} = at) do
    with %{} = failure <- ContactStartFailure.open_failure(contact),
         {:ok, current} <-
           ContactStore.fetch_scheduled(contact.mission_id, contact.scheduled_contact_id),
         {:ok, updated} <-
           ContactStore.update_scheduled_lifecycle(current, current.lifecycle_state, %{
             "start_failure" => Map.put(failure, "realized_at", DateTime.to_iso8601(at))
           }) do
      announce(updated)
    else
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp log_first(
         %ScheduledContact{metadata: %{"start_failure" => %{"attempts" => 1} = failure}} = c,
         error
       ) do
    Logger.warning(
      "Pass #{c.scheduled_contact_id} (mission #{c.mission_id}) couldn't be set up: " <>
        "#{failure["reason"]}; #{inspect(error, limit: 10, printable_limit: 200)}"
    )
  end

  defp log_first(_contact, _error), do: :ok

  defp announce(%ScheduledContact{organization_id: org, mission_id: mission})
       when is_binary(org) do
    ScopedReadUpdates.publish(:attention_changed, org, mission)
    :ok
  end

  defp announce(%ScheduledContact{}), do: :ok
end
