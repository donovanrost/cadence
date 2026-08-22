defmodule Cadence.Runtime.ManagedRecords do
  @moduledoc "Data-plane persistence boundary for managed-capability execution records."

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Runtime.{ManagedActionRequest, ManagedCapabilityRecord, ManagedTimerEvent}

  alias Cadence.Runtime.ManagedRecords.{
    ManagedActionRequestRow,
    ManagedCapabilityRecordRow,
    ManagedTimerEventRow
  }

  alias Ecto.Multi

  @spec add_capability_record_inserts(Multi.t(), [ManagedCapabilityRecord.t()]) :: Multi.t()
  def add_capability_record_inserts(%Multi{} = multi, records) when is_list(records) do
    Enum.reduce(records, multi, fn %ManagedCapabilityRecord{} = record, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_capability_record, record.capability_record_id},
        ManagedCapabilityRecordRow.changeset(record)
      )
    end)
  end

  @spec add_action_request_inserts(Multi.t(), [ManagedActionRequest.t()]) :: Multi.t()
  def add_action_request_inserts(%Multi{} = multi, requests) when is_list(requests) do
    Enum.reduce(requests, multi, fn %ManagedActionRequest{} = request, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_action_request, request.action_request_id},
        ManagedActionRequestRow.changeset(request)
      )
    end)
  end

  @spec add_timer_event_inserts(Multi.t(), [ManagedTimerEvent.t()]) :: Multi.t()
  def add_timer_event_inserts(%Multi{} = multi, events) when is_list(events) do
    Enum.reduce(events, multi, fn %ManagedTimerEvent{} = event, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_timer_event, event.timer_event_id},
        ManagedTimerEventRow.changeset(event)
      )
    end)
  end

  @spec list_action_requests(binary()) :: [ManagedActionRequest.t()]
  def list_action_requests(mission_id) when is_binary(mission_id) do
    ManagedActionRequestRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.all()
    |> Enum.map(&ManagedActionRequestRow.to_domain/1)
  end
end
