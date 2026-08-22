defmodule Cadence.Contacts.SchedulerReadModel do
  @moduledoc """
  Pure scheduler wakeup calculation and per-mission contact projections.
  """

  alias Cadence.Contacts.ScheduledContact

  @type projection :: %{
          scheduled_contacts: %{optional(binary()) => ScheduledContact.t()}
        }

  @type wakeup :: %{mission_id: binary(), wake_at: DateTime.t()}

  @spec next_wakeup([wakeup()], binary()) :: DateTime.t() | nil
  def next_wakeup(wakeups, mission_id) when is_list(wakeups) and is_binary(mission_id) do
    Enum.find_value(wakeups, fn
      %{mission_id: ^mission_id, wake_at: wake_at} -> wake_at
      _other -> nil
    end)
  end

  @spec wakeups([ScheduledContact.t()], [wakeup()], DateTime.t()) :: [wakeup()]
  def wakeups(scheduled_contacts, active_realized_wakeups, %DateTime{} = reference_time)
      when is_list(scheduled_contacts) and is_list(active_realized_wakeups) do
    scheduled_wakeups =
      Enum.flat_map(
        scheduled_contacts,
        &scheduled_contact_wakeups(&1, reference_time)
      )

    normalized_realized_wakeups =
      Enum.map(active_realized_wakeups, &normalize_wakeup(&1, reference_time))

    scheduled_wakeups
    |> Kernel.++(normalized_realized_wakeups)
    |> group_wakeups()
  end

  @spec projection([ScheduledContact.t()]) :: projection()
  def projection(scheduled_contacts) when is_list(scheduled_contacts) do
    %{
      scheduled_contacts: Map.new(scheduled_contacts, &{&1.scheduled_contact_id, &1})
    }
  end

  defp scheduled_contact_wakeups(%ScheduledContact{} = contact, reference_time) do
    case contact.lifecycle_state do
      :scheduled -> scheduled_contact_scheduled_wakeup(contact, reference_time)
      :realized -> scheduled_contact_realized_wakeup(contact, reference_time)
    end
  end

  defp scheduled_contact_scheduled_wakeup(
         %ScheduledContact{ends_at: %DateTime{} = ends_at} = contact,
         reference_time
       ) do
    cond do
      DateTime.compare(ends_at, reference_time) != :gt ->
        [%{mission_id: contact.mission_id, wake_at: reference_time}]

      DateTime.compare(contact.starts_at, reference_time) != :gt ->
        [%{mission_id: contact.mission_id, wake_at: reference_time}]

      true ->
        [%{mission_id: contact.mission_id, wake_at: contact.starts_at}]
    end
  end

  defp scheduled_contact_scheduled_wakeup(%ScheduledContact{} = contact, reference_time) do
    if DateTime.compare(contact.starts_at, reference_time) == :gt do
      [%{mission_id: contact.mission_id, wake_at: contact.starts_at}]
    else
      [%{mission_id: contact.mission_id, wake_at: reference_time}]
    end
  end

  defp scheduled_contact_realized_wakeup(%ScheduledContact{ends_at: nil}, _reference_time),
    do: []

  defp scheduled_contact_realized_wakeup(
         %ScheduledContact{ends_at: ends_at} = contact,
         reference_time
       ) do
    [%{mission_id: contact.mission_id, wake_at: max_datetime(ends_at, reference_time)}]
  end

  defp normalize_wakeup(%{wake_at: %DateTime{} = wake_at} = wakeup, reference_time) do
    %{wakeup | wake_at: max_datetime(wake_at, reference_time)}
  end

  defp group_wakeups(wakeups) do
    wakeups
    |> Enum.group_by(& &1.mission_id)
    |> Enum.map(fn {mission_id, mission_wakeups} ->
      %{
        mission_id: mission_id,
        wake_at: Enum.min_by(mission_wakeups, &datetime_sort_key(&1.wake_at)).wake_at
      }
    end)
  end

  defp max_datetime(%DateTime{} = datetime, %DateTime{} = minimum) do
    if DateTime.compare(datetime, minimum) == :lt, do: minimum, else: datetime
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
end
