defmodule Cadence.ApplicationDispatch.Dispatcher do
  @moduledoc """
  Applies governed binding rules to canonical packet records and executes the
  selected handlers.
  """

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityInstance,
    DispatchDecision,
    Registry,
    WorkItem
  }

  alias Cadence.Ids
  alias Cadence.Protocol.PacketRecord

  @spec dispatch(PacketRecord.t(), BindingSet.t(), Registry.t()) ::
          {:ok, DispatchDecision.t()} | {:error, term()}
  def dispatch(
        %PacketRecord{} = packet_record,
        %BindingSet{} = binding_set,
        registry \\ Registry.default()
      ) do
    matched_rules =
      binding_set.rules
      |> Enum.filter(&matches?(&1, packet_record))
      |> select_best_rules()
      |> Enum.sort_by(& &1.priority)

    capability_instances_by_id = capability_instances_by_id(binding_set)

    with :ok <- validate_handlers(matched_rules, capability_instances_by_id, registry) do
      {:ok, build_decision(packet_record, binding_set, matched_rules)}
    end
  end

  @spec execute(PacketRecord.t(), DispatchDecision.t(), Registry.t()) ::
          {:ok, [term()]} | {:error, term()}
  def execute(packet_record, decision, registry \\ Registry.default())

  def execute(%PacketRecord{} = packet_record, %DispatchDecision{} = decision, registry) do
    do_execute(packet_record, decision, registry)
  end

  def execute(_packet_record, %DispatchDecision{status: status}, _registry)
      when status in [:unmatched, :ambiguous] do
    {:ok, []}
  end

  defp do_execute(%PacketRecord{} = packet_record, %DispatchDecision{} = decision, registry) do
    Enum.reduce_while(decision.work_items, {:ok, []}, fn %WorkItem{} = work_item, {:ok, acc} ->
      case Registry.fetch(registry, work_item.handler_key) do
        {:ok, handler_module} ->
          execute_work_item(handler_module, packet_record, work_item, acc)

        :error ->
          {:halt, {:error, {:unknown_handler, work_item.handler_key}}}
      end
    end)
  end

  defp execute_work_item(
         handler_module,
         %PacketRecord{} = packet_record,
         %WorkItem{} = work_item,
         acc
       ) do
    case handler_module.handle(packet_record, work_item) do
      {:ok, outputs} -> {:cont, {:ok, acc ++ outputs}}
      {:error, reason} -> {:halt, {:error, {work_item.handler_key, reason}}}
    end
  end

  defp matches?(%BindingRule{} = rule, %PacketRecord{} = packet_record) do
    matches_source_endpoint?(rule, packet_record) and
      matches_packet_kind?(rule, packet_record) and matches_apid?(rule, packet_record)
  end

  defp matches_source_endpoint?(%BindingRule{} = rule, %PacketRecord{} = packet_record) do
    case BindingRule.source_endpoint_ref(rule) do
      nil -> true
      _source_endpoint_ref -> do_matches_source_endpoint?(rule, packet_record)
    end
  end

  defp do_matches_source_endpoint?(
         %BindingRule{} = rule,
         %PacketRecord{source_endpoint_ref: source_endpoint_ref}
       ) do
    BindingRule.source_endpoint_ref(rule) == source_endpoint_ref
  end

  defp matches_packet_kind?(
         %BindingRule{} = rule,
         %PacketRecord{} = packet_record
       ) do
    case BindingRule.packet_kind(rule) do
      nil -> true
      packet_kind -> packet_kind == packet_record.packet_kind
    end
  end

  defp matches_apid?(%BindingRule{} = rule, %PacketRecord{apid: apid}) do
    case BindingRule.apid(rule) do
      nil -> true
      selector_apid -> selector_apid == apid
    end
  end

  defp validate_handlers(rules, capability_instances_by_id, registry) do
    case Enum.find_value(rules, fn %BindingRule{} = rule ->
           with {:ok, %CapabilityInstance{} = capability_instance} <-
                  fetch_capability_instance(rule, capability_instances_by_id),
                :error <- Registry.fetch(registry, capability_instance.family_key) do
             {:unknown_handler, capability_instance.family_key}
           else
             {:error, reason} -> reason
             {:ok, _family_module} -> nil
           end
         end) do
      nil -> :ok
      reason -> {:error, reason}
    end
  end

  defp select_best_rules([]), do: []

  defp select_best_rules(matched_rules) when is_list(matched_rules) do
    best_specificity =
      matched_rules
      |> Enum.map(&specificity_score/1)
      |> Enum.max()

    Enum.filter(matched_rules, &(specificity_score(&1) == best_specificity))
  end

  defp specificity_score(%BindingRule{} = rule) do
    Enum.count(
      [
        BindingRule.source_endpoint_ref(rule),
        BindingRule.packet_kind(rule),
        BindingRule.apid(rule)
      ],
      &present?/1
    )
  end

  defp present?(nil), do: false
  defp present?(_value), do: true

  defp build_decision(%PacketRecord{} = packet_record, %BindingSet{} = binding_set, []) do
    %DispatchDecision{
      dispatch_decision_id: Ids.new("dispatch"),
      packet_id: packet_record.packet_id,
      evidence_id: packet_record.evidence_id,
      binding_set_id: binding_set.binding_set_id,
      binding_set_version: binding_set.version,
      status: :unmatched,
      anomalies: [:no_matching_binding_rules]
    }
  end

  defp build_decision(%PacketRecord{} = packet_record, %BindingSet{} = binding_set, matched_rules) do
    {status, anomalies, work_items} =
      if ambiguous?(matched_rules) do
        {:ambiguous, [:ambiguous_binding_rules], []}
      else
        {:matched, [], Enum.map(matched_rules, &to_work_item(&1, binding_set))}
      end

    %DispatchDecision{
      dispatch_decision_id: Ids.new("dispatch"),
      packet_id: packet_record.packet_id,
      evidence_id: packet_record.evidence_id,
      binding_set_id: binding_set.binding_set_id,
      binding_set_version: binding_set.version,
      status: status,
      matched_rule_ids: Enum.map(matched_rules, & &1.binding_rule_id),
      anomalies: anomalies,
      work_items: work_items
    }
  end

  defp ambiguous?([_single]), do: false

  defp ambiguous?(matched_rules) when is_list(matched_rules) do
    Enum.any?(matched_rules, &(&1.fanout_mode == :exclusive))
  end

  defp capability_instances_by_id(%BindingSet{} = binding_set) do
    Map.new(binding_set.capability_instances, fn %CapabilityInstance{} = capability_instance ->
      {capability_instance.capability_instance_id, capability_instance}
    end)
  end

  defp fetch_capability_instance(%BindingRule{} = rule, capability_instances_by_id) do
    case Map.fetch(capability_instances_by_id, BindingRule.capability_instance_id(rule)) do
      {:ok, %CapabilityInstance{} = capability_instance} -> {:ok, capability_instance}
      :error -> {:error, {:unknown_capability_instance, BindingRule.capability_instance_id(rule)}}
    end
  end

  defp to_work_item(%BindingRule{} = rule, %BindingSet{} = binding_set) do
    case BindingSet.fetch_capability_instance(
           binding_set,
           BindingRule.capability_instance_id(rule)
         ) do
      {:ok, %CapabilityInstance{} = capability_instance} ->
        %WorkItem{
          binding_rule_id: rule.binding_rule_id,
          capability_instance_id: capability_instance.capability_instance_id,
          handler_key: capability_instance.family_key,
          handler_configuration: capability_instance.runtime_configuration
        }

      :error ->
        %WorkItem{
          binding_rule_id: rule.binding_rule_id,
          capability_instance_id: BindingRule.capability_instance_id(rule),
          handler_key: rule.handler_key,
          handler_configuration: rule.handler_configuration
        }
    end
  end
end
