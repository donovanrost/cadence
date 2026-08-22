defmodule Cadence.Telemetry.DataManagement.ObservationIdentityDecisions do
  @moduledoc false

  alias Cadence.Telemetry.Storage

  @decisions [
    :mark_canonical,
    :mark_conflict,
    :mark_superseded,
    :mark_advisory
  ]

  def apply_decision(observation_identity_id, decision, attrs, opts)
      when is_binary(observation_identity_id) and (is_atom(decision) or is_binary(decision)) and
             is_map(attrs) and is_list(opts) do
    with {:ok, decision} <- normalize_decision(decision),
         :ok <- require_context(attrs),
         {:ok, decision_opts} <- decision_opts(attrs, opts) do
      Storage.apply_observation_identity_decision(
        observation_identity_id,
        decision,
        decision_opts
      )
    end
  end

  def apply_decisions(items, decision, attrs, opts)
      when is_list(items) and (is_atom(decision) or is_binary(decision)) and is_map(attrs) and
             is_list(opts) do
    with {:ok, decision} <- normalize_decision(decision),
         :ok <- require_context(attrs),
         :ok <- require_items(items) do
      items
      |> apply_items(decision, attrs, opts)
      |> then(&{:ok, &1})
    end
  end

  defp decision_opts(attrs, opts) do
    attrs
    |> Map.take([
      :organization_id,
      :mission_id,
      :realm,
      :data_source_id,
      :binding_id,
      :canonical_observation_id,
      :canonical_sample_id,
      :canonical_revision,
      :decision_reason,
      :reason,
      :decided_at,
      :operator_id,
      :actor_id,
      :actor_kind
    ])
    |> Map.put(:evidence_ref, evidence_ref(attrs))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.new()
    |> Keyword.merge(Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache]))
    |> Keyword.merge(Keyword.get(opts, :decision_opts, []))
    |> then(&{:ok, &1})
  end

  defp require_items([]), do: {:error, :empty_observation_identity_decision_batch}
  defp require_items(_items), do: :ok

  defp apply_items(items, decision, attrs, opts) do
    item_count = length(items)

    items
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {item, item_index}, acc ->
      item
      |> apply_item(item_index, item_count, decision, attrs, opts)
      |> collect_item(acc)
    end)
    |> batch_summary(decision, attrs, item_count)
  end

  defp collect_item({:ok, result}, {results, errors}), do: {[result | results], errors}
  defp collect_item({:error, error}, {results, errors}), do: {results, [error | errors]}

  defp apply_item(item, item_index, item_count, decision, attrs, opts) when is_map(item) do
    observation_identity_id = get_attr(item, :observation_identity_id)

    if is_binary(observation_identity_id) and String.trim(observation_identity_id) != "" do
      item_attrs =
        attrs
        |> Map.merge(item_attrs(item))
        |> Map.put(:observation_identity_id, observation_identity_id)
        |> put_compact_attr(:decision_item_index, item_index)
        |> put_compact_attr(:decision_item_count, item_count)
        |> put_compact_attr(:evidence_ref, item_evidence(item, attrs, item_index, item_count))

      case apply_decision(observation_identity_id, decision, item_attrs, opts) do
        {:ok, state} ->
          {:ok,
           %{
             index: item_index,
             observation_identity_id: observation_identity_id,
             validity_state: state.validity_state,
             canonical_observation_id: state.canonical_observation_id,
             canonical_sample_id: state.canonical_sample_id,
             canonical_revision: state.canonical_revision
           }}

        {:error, reason} ->
          {:error,
           %{
             index: item_index,
             observation_identity_id: observation_identity_id,
             reason: reason
           }}
      end
    else
      {:error,
       %{
         index: item_index,
         observation_identity_id: nil,
         reason: {:missing_field, :observation_identity_id}
       }}
    end
  end

  defp apply_item(item, item_index, _item_count, _decision, _attrs, _opts) do
    {:error,
     %{
       index: item_index,
       observation_identity_id: nil,
       reason: {:invalid_observation_identity_decision_item, item}
     }}
  end

  defp item_attrs(item) do
    %{}
    |> put_compact_attr(:canonical_observation_id, get_attr(item, :canonical_observation_id))
    |> put_compact_attr(:canonical_sample_id, get_attr(item, :canonical_sample_id))
    |> put_compact_attr(:canonical_revision, get_attr(item, :canonical_revision))
    |> put_compact_attr(:decision_reason, get_attr(item, :decision_reason))
  end

  defp item_evidence(item, attrs, item_index, item_count) do
    attrs
    |> get_attr(:evidence_ref, %{})
    |> ensure_map()
    |> Map.merge(ensure_map(get_attr(item, :evidence_ref, %{})))
    |> Map.put(
      "bulk_workflow_item",
      %{
        "kind" => "telemetry_correction_authority_workflow_item",
        "workflow_id" =>
          get_attr(attrs, :correction_workflow_id) ||
            get_attr(attrs, :workflow_id) ||
            get_attr(attrs, :decision_workflow_id),
        "item_index" => item_index,
        "item_count" => item_count,
        "observation_identity_id" => get_attr(item, :observation_identity_id),
        "selection_kind" => get_attr(attrs, :selection_kind)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()
    )
  end

  defp batch_summary({results, errors}, decision, attrs, item_count) do
    results = Enum.reverse(results)
    errors = Enum.reverse(errors)

    %{
      decision: decision,
      workflow_id:
        get_attr(attrs, :correction_workflow_id) ||
          get_attr(attrs, :workflow_id) ||
          get_attr(attrs, :decision_workflow_id),
      requested: item_count,
      applied: length(results),
      failed: length(errors),
      results: results,
      errors: errors
    }
  end

  defp evidence_ref(attrs) do
    evidence_ref = ensure_map(get_attr(attrs, :evidence_ref, %{}))

    attrs
    |> workflow_evidence()
    |> case do
      workflow_evidence when workflow_evidence == %{} ->
        evidence_ref

      workflow_evidence when evidence_ref == %{} ->
        workflow_evidence

      workflow_evidence ->
        Map.put(evidence_ref, "correction_workflow", workflow_evidence)
    end
  end

  defp workflow_evidence(attrs) do
    workflow_id =
      get_attr(attrs, :correction_workflow_id) ||
        get_attr(attrs, :workflow_id) ||
        get_attr(attrs, :decision_workflow_id)

    %{
      "kind" => "telemetry_correction_authority_workflow",
      "id" => workflow_id,
      "authority" => get_attr(attrs, :authority),
      "requested_by" => get_attr(attrs, :requested_by),
      "operator_id" => get_attr(attrs, :operator_id) || get_attr(attrs, :actor_id),
      "reason" => get_attr(attrs, :decision_reason) || get_attr(attrs, :reason),
      "item_index" => get_attr(attrs, :decision_item_index),
      "item_count" => get_attr(attrs, :decision_item_count),
      "item_observation_identity_id" => get_attr(attrs, :observation_identity_id),
      "selection_kind" => get_attr(attrs, :selection_kind)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp normalize_decision(decision) when decision in @decisions, do: {:ok, decision}

  defp normalize_decision(decision) when is_binary(decision) do
    normalized =
      decision
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    case Enum.find(@decisions, &(Atom.to_string(&1) == normalized)) do
      nil -> {:error, {:unsupported_observation_identity_decision, decision}}
      decision -> {:ok, decision}
    end
  end

  defp normalize_decision(decision),
    do: {:error, {:unsupported_observation_identity_decision, decision}}

  defp require_context(attrs) do
    [:organization_id, :mission_id, :data_source_id, :binding_id]
    |> Enum.reduce_while(:ok, fn field, :ok ->
      case require_present(attrs, field) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> require_realm(attrs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_present(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> :ok
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp require_realm(attrs) do
    if is_nil(get_attr(attrs, :realm)) do
      {:error, {:missing_field, :realm}}
    else
      :ok
    end
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp put_compact_attr(attrs, _key, value) when value in [nil, ""], do: attrs
  defp put_compact_attr(attrs, key, value) when is_map(attrs), do: Map.put(attrs, key, value)

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
