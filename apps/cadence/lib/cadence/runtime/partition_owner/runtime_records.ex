defmodule Cadence.Runtime.PartitionOwner.RuntimeRecords do
  @moduledoc false

  alias Cadence.ApplicationDispatch.CapabilityInstance
  alias Cadence.Capabilities.{ExecutionContext, ExecutionResult}
  alias Cadence.Ids
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Runtime.{ManagedActionRequest, ManagedCapabilityRecord, ManagedTimerEvent}

  def empty do
    %{
      capability_records: [],
      action_requests: [],
      timer_events: []
    }
  end

  def merge(left, right) do
    %{
      capability_records: left.capability_records ++ right.capability_records,
      action_requests: left.action_requests ++ right.action_requests,
      timer_events: left.timer_events ++ right.timer_events
    }
  end

  def for_execution(
        event_kind,
        %CapabilityInstance{} = capability_instance,
        %ExecutionContext{} = execution_context,
        %ExecutionResult{} = execution_result,
        action_requests,
        timer_events,
        opts \\ []
      ) do
    packet_record = Keyword.get(opts, :packet_record)
    timer_key = Keyword.get(opts, :timer_key)
    state_snapshot = Keyword.get(opts, :state_snapshot)

    %{
      capability_records: [
        build_managed_capability_record(
          event_kind,
          capability_instance,
          execution_context,
          execution_result,
          action_requests,
          packet_record,
          timer_key,
          state_snapshot
        )
      ],
      action_requests:
        Enum.map(action_requests, fn action_request ->
          build_managed_action_request(
            capability_instance,
            execution_context,
            action_request,
            packet_record
          )
        end),
      timer_events:
        Enum.map(timer_events, fn timer_event ->
          timer_event(
            capability_instance,
            execution_context,
            timer_event,
            packet_record
          )
        end)
    }
  end

  defp build_managed_capability_record(
         event_kind,
         %CapabilityInstance{} = capability_instance,
         %ExecutionContext{} = execution_context,
         %ExecutionResult{} = execution_result,
         action_requests,
         packet_record,
         timer_key,
         state_snapshot
       ) do
    %ManagedCapabilityRecord{
      capability_record_id: Ids.new("capability_record"),
      mission_id: execution_context.mission_id,
      capability_instance_id: capability_instance.capability_instance_id,
      family_key: capability_instance.family_key,
      activation_id: execution_context.activation_id,
      binding_set_id: execution_context.binding_set_id,
      binding_set_version: execution_context.binding_set_version,
      partition_affinity: execution_context.partition_key.affinity,
      partition_value: execution_context.partition_key.value,
      event_kind: event_kind,
      packet_id: packet_id(packet_record),
      evidence_id: evidence_id(packet_record),
      timer_key: timer_key,
      emitted_record_kinds: Enum.map(execution_result.records, &record_kind/1),
      emitted_record_count: length(execution_result.records),
      action_request_count: length(action_requests),
      state_snapshot: state_snapshot || execution_result.state || %{},
      recorded_at: execution_context.current_time,
      metadata: execution_context.metadata
    }
  end

  defp build_managed_action_request(
         %CapabilityInstance{} = capability_instance,
         %ExecutionContext{} = execution_context,
         action_request,
         packet_record
       ) do
    %ManagedActionRequest{
      action_request_id: Ids.new("managed_action_request"),
      mission_id: execution_context.mission_id,
      capability_instance_id: capability_instance.capability_instance_id,
      family_key: capability_instance.family_key,
      activation_id: execution_context.activation_id,
      binding_set_id: execution_context.binding_set_id,
      binding_set_version: execution_context.binding_set_version,
      partition_affinity: execution_context.partition_key.affinity,
      partition_value: execution_context.partition_key.value,
      action_kind: action_kind(action_request),
      packet_id: packet_id(packet_record),
      evidence_id: evidence_id(packet_record),
      request_document: Map.from_struct(action_request),
      requested_at: execution_context.current_time
    }
  end

  def timer_event(
        %CapabilityInstance{} = capability_instance,
        %ExecutionContext{} = execution_context,
        timer_event,
        packet_record
      ) do
    %ManagedTimerEvent{
      timer_event_id: Ids.new("managed_timer_event"),
      mission_id: execution_context.mission_id,
      capability_instance_id: capability_instance.capability_instance_id,
      family_key: capability_instance.family_key,
      activation_id: execution_context.activation_id,
      binding_set_id: execution_context.binding_set_id,
      binding_set_version: execution_context.binding_set_version,
      partition_affinity: execution_context.partition_key.affinity,
      partition_value: execution_context.partition_key.value,
      timer_key: Map.fetch!(timer_event, :timer_key),
      event_kind: Map.fetch!(timer_event, :event_kind),
      packet_id: packet_id(packet_record),
      evidence_id: evidence_id(packet_record),
      due_at: Map.get(timer_event, :due_at),
      occurred_at: execution_context.current_time,
      metadata: Map.get(timer_event, :metadata, %{})
    }
  end

  defp action_kind(%Cadence.ActionRequests.ScheduleTimer{}), do: :schedule_timer
  defp action_kind(%Cadence.ActionRequests.CancelTimer{}), do: :cancel_timer

  defp action_kind(action_request) do
    raise ArgumentError, "unsupported managed action request: #{inspect(action_request)}"
  end

  defp record_kind(%Cadence.Telemetry.Sample{}), do: :telemetry_sample

  defp record_kind(record) do
    record
    |> struct_name_parts()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp struct_name_parts(%struct_module{}) when is_atom(struct_module) do
    struct_module
    |> Module.split()
  end

  defp packet_id(%PacketRecord{packet_id: packet_id}), do: packet_id
  defp packet_id(_other), do: nil

  defp evidence_id(%PacketRecord{evidence_id: evidence_id}), do: evidence_id
  defp evidence_id(_other), do: nil
end
