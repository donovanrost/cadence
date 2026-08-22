defmodule Cadence.Contacts.Validation do
  @moduledoc """
  Pure validation rules for contact configuration and lifecycle workflows.
  """

  alias Cadence.Contacts.{RealizedContact, ScheduledContact}

  @spec scheduled_contact(ScheduledContact.t(), [term()]) :: :ok | {:error, term()}
  def scheduled_contact(%ScheduledContact{} = scheduled_contact, resolved_paths)
      when is_list(resolved_paths) do
    with :ok <- mission_id(scheduled_contact.mission_id),
         :ok <- starts_before_end(scheduled_contact.starts_at, scheduled_contact.ends_at),
         :ok <- non_empty_paths(resolved_paths),
         :ok <- selected_path_presence(resolved_paths),
         :ok <- contact_intents(resolved_paths, scheduled_contact.contact_intents) do
      unique_path_ids(resolved_paths)
    end
  end

  @spec realized_contact(RealizedContact.t()) :: :ok | {:error, :missing_mission_id}
  def realized_contact(%RealizedContact{} = realized_contact) do
    mission_id(realized_contact.mission_id)
  end

  @spec mission_id(term()) :: :ok | {:error, :missing_mission_id}
  def mission_id(mission_id) when is_binary(mission_id) and mission_id != "", do: :ok
  def mission_id(_mission_id), do: {:error, :missing_mission_id}

  @spec required_binary(term(), term()) :: :ok | {:error, term()}
  def required_binary(value, _reason) when is_binary(value) and value != "", do: :ok
  def required_binary(_value, reason), do: {:error, reason}

  @spec reusable_path_refs([term()]) ::
          :ok | {:error, :duplicate_contact_runtime_config_reference}
  def reusable_path_refs(refs) when is_list(refs) do
    if length(refs) == MapSet.size(MapSet.new(refs)) do
      :ok
    else
      {:error, :duplicate_contact_runtime_config_reference}
    end
  end

  @spec unique_path_ids([term()]) :: :ok | {:error, :duplicate_scheduled_contact_path_id}
  def unique_path_ids(paths) when is_list(paths) do
    path_ids = Enum.map(paths, & &1.path_id)

    if length(path_ids) == MapSet.size(MapSet.new(path_ids)) do
      :ok
    else
      {:error, :duplicate_scheduled_contact_path_id}
    end
  end

  @spec schedule_realization(ScheduledContact.t()) :: :ok | {:error, term()}
  def schedule_realization(%ScheduledContact{lifecycle_state: :scheduled}), do: :ok

  def schedule_realization(%ScheduledContact{lifecycle_state: :realized}),
    do: {:error, :scheduled_contact_already_realized}

  def schedule_realization(%ScheduledContact{lifecycle_state: :completed}),
    do: {:error, :scheduled_contact_completed}

  def schedule_realization(%ScheduledContact{lifecycle_state: :expired}),
    do: {:error, :scheduled_contact_expired}

  def schedule_realization(%ScheduledContact{lifecycle_state: :canceled}),
    do: {:error, :scheduled_contact_canceled}

  defp starts_before_end(%DateTime{} = _starts_at, nil), do: :ok

  defp starts_before_end(%DateTime{} = starts_at, %DateTime{} = ends_at) do
    case DateTime.compare(starts_at, ends_at) do
      :gt -> {:error, :scheduled_contact_ends_before_it_starts}
      _other -> :ok
    end
  end

  defp starts_before_end(_starts_at, _ends_at),
    do: {:error, :scheduled_contact_requires_start_time}

  defp non_empty_paths([]), do: {:error, :scheduled_contact_requires_path_configuration}
  defp non_empty_paths(_paths), do: :ok

  defp selected_path_presence(paths) do
    if Enum.any?(paths, &(&1.selection_role == :selected)) do
      :ok
    else
      {:error, :scheduled_contact_requires_selected_path}
    end
  end

  defp contact_intents(paths, contact_intents) do
    with :ok <- telemetry_downlink_intent(paths, contact_intents) do
      command_window_intent(paths, contact_intents)
    end
  end

  defp telemetry_downlink_intent(paths, contact_intents) do
    if :telemetry_downlink in contact_intents and not selected_direction?(paths, :downlink) do
      {:error, :scheduled_contact_requires_selected_downlink_path}
    else
      :ok
    end
  end

  defp command_window_intent(paths, contact_intents) do
    if :command_window in contact_intents and not selected_direction?(paths, :uplink) do
      {:error, :scheduled_contact_requires_selected_uplink_path}
    else
      :ok
    end
  end

  defp selected_direction?(paths, direction) do
    Enum.any?(paths, &(&1.direction == direction and &1.selection_role == :selected))
  end
end
