defmodule Cadence.Telemetry.DataManagement.LateDataPolicy do
  @moduledoc false

  alias Cadence.Telemetry.DataManagement.HistoricalSourceSamples
  alias Cadence.Telemetry.Storage

  @decisions [:accept, :reject]

  def record(decision, attrs, opts)
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    with {:ok, decision} <- normalize_decision(decision),
         :ok <- require_context(attrs),
         {:ok, event_attrs} <- event_attrs(decision, attrs) do
      Storage.record_backfill_lifecycle_event(
        event_attrs,
        Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
      )
    end
  end

  def execute(decision, attrs, opts)
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    with {:ok, decision} <- normalize_decision(decision),
         :ok <- require_context(attrs),
         {:ok, samples, diagnostics} <- HistoricalSourceSamples.fetch(attrs),
         :ok <- persist_samples(decision, samples, attrs, opts),
         {:ok, event_attrs} <- event_attrs(decision, attrs, samples, diagnostics),
         {:ok, event} <-
           Storage.record_backfill_lifecycle_event(
             event_attrs,
             Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
           ) do
      {:ok, %{event: event, sample_count: length(samples), diagnostics: diagnostics}}
    end
  end

  def execution_mode(attrs) when is_map(attrs) do
    if Enum.all?(
         [
           get_attr(attrs, :point_id),
           get_attr(attrs, :source_from),
           get_attr(attrs, :source_to)
         ],
         &present?/1
       ) do
      :sample_execution
    else
      :event_only
    end
  end

  def execution_mode(_attrs), do: :event_only

  def write_opts(decision, opts)
      when (is_atom(decision) or is_binary(decision)) and is_list(opts) do
    with {:ok, decision} <- normalize_decision(decision) do
      {:ok, merge_write_opts(decision, opts)}
    end
  end

  defp present?(value), do: value not in [nil, ""]

  defp persist_samples(_decision, [], _attrs, _opts), do: :ok

  defp persist_samples(decision, samples, attrs, opts) do
    with {:ok, write_opts} <- sample_write_opts(decision, attrs, opts) do
      Storage.persist_samples(samples, write_opts)
    end
  end

  defp sample_write_opts(decision, attrs, opts) do
    base_opts =
      [
        organization_id: get_attr(attrs, :organization_id),
        realm: get_attr(attrs, :realm),
        data_source_id: get_attr(attrs, :data_source_id),
        binding_id: get_attr(attrs, :binding_id),
        source_endpoint_id: get_attr(attrs, :source_endpoint_id),
        replay_run_id: get_attr(attrs, :replay_run_id),
        recorded_at: get_attr(attrs, :recorded_at),
        metadata: get_attr(attrs, :metadata, %{}),
        revision: get_attr(attrs, :revision),
        supersedes_observation_id: get_attr(attrs, :supersedes_observation_id),
        dashboard_runtime_invalidation?:
          Keyword.get(opts, :dashboard_runtime_invalidation?, true),
        dashboard_runtime_cache: Keyword.get(opts, :dashboard_runtime_cache),
        record_backfill_lifecycle_event?: false,
        backfill_run_id: get_attr(attrs, :backfill_run_id),
        reason: get_attr(attrs, :reason) || "late_data_policy_write",
        actor_id: get_attr(attrs, :actor_id),
        actor_kind: get_attr(attrs, :actor_kind)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    write_opts(decision, base_opts)
  end

  defp event_attrs(decision, attrs) do
    event_attrs(decision, attrs, nil, nil)
  end

  defp event_attrs(decision, attrs, samples, diagnostics) do
    with {:ok, source_from} <- optional_datetime_attr(attrs, :source_from),
         {:ok, source_to} <- optional_datetime_attr(attrs, :source_to),
         {:ok, receipt_from} <- optional_datetime_attr(attrs, :receipt_from),
         {:ok, receipt_to} <- optional_datetime_attr(attrs, :receipt_to) do
      attrs =
        attrs
        |> base_attrs()
        |> Map.merge(%{
          event_type: event_type(decision),
          authority: authority(decision, attrs),
          reason: reason(decision, attrs),
          source_from: source_from,
          source_to: source_to,
          receipt_from: receipt_from,
          receipt_to: receipt_to,
          sample_count: sample_count(attrs, samples),
          payload: payload(decision, attrs, samples, diagnostics)
        })
        |> compact_attrs()

      {:ok, attrs}
    end
  end

  defp base_attrs(attrs) do
    %{
      backfill_run_id: get_attr(attrs, :backfill_run_id),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      realm: get_attr(attrs, :realm),
      data_source_id: get_attr(attrs, :data_source_id),
      binding_id: get_attr(attrs, :binding_id),
      observable_id: get_attr(attrs, :observable_id),
      point_id: get_attr(attrs, :point_id),
      spacecraft_id: get_attr(attrs, :spacecraft_id),
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind)
    }
  end

  defp event_type(:accept), do: :late_data_accepted
  defp event_type(:reject), do: :late_data_rejected

  defp authority(:accept, attrs), do: get_attr(attrs, :authority) || :authoritative
  defp authority(:reject, attrs), do: get_attr(attrs, :authority) || :advisory

  defp reason(decision, attrs) do
    get_attr(attrs, :reason) || "dashboard_late_data_#{decision}"
  end

  defp sample_count(_attrs, samples) when is_list(samples), do: length(samples)

  defp sample_count(attrs, _samples) do
    case get_attr(attrs, :sample_count) do
      count when is_integer(count) and count >= 0 -> count
      count when is_binary(count) -> parse_non_negative_integer(count)
      _count -> nil
    end
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> nil
    end
  end

  defp payload(decision, attrs, samples, diagnostics) do
    execution_mode = payload_execution_mode(attrs, samples)

    attrs
    |> get_attr(:payload, %{})
    |> ensure_map()
    |> Map.merge(%{
      "kind" => "late_data_policy_decision",
      "policy_decision" => Atom.to_string(decision),
      "execution_mode" => Atom.to_string(execution_mode),
      "write_validity_state" => decision |> validity_state() |> Atom.to_string(),
      "record_current_values" => record_current_values?(decision, execution_mode),
      "refresh_latest_value" => refresh_latest_value?(decision, execution_mode),
      "projection_effect" => projection_effect(decision, execution_mode),
      "source_event_id" => get_attr(attrs, :source_event_id),
      "source_event_type" => get_attr(attrs, :source_event_type),
      "requested_by" => get_attr(attrs, :requested_by) || "dashboard_data_link_inspector",
      "selected_sample_count" => selected_sample_count(samples),
      "source" => diagnostics
    })
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp selected_sample_count(samples) when is_list(samples), do: length(samples)
  defp selected_sample_count(_samples), do: nil

  defp payload_execution_mode(attrs, samples) do
    case get_attr(attrs, :execution_mode) do
      mode when mode in [:sample_execution, "sample_execution"] -> :sample_execution
      mode when mode in [:event_only, "event_only"] -> :event_only
      _mode when is_list(samples) -> :sample_execution
      _mode -> :event_only
    end
  end

  defp merge_write_opts(decision, opts) do
    opts
    |> Keyword.merge(locked_write_opts(decision))
    |> Keyword.update(
      :metadata,
      metadata(decision),
      &Map.merge(ensure_map(&1), metadata(decision))
    )
  end

  defp locked_write_opts(decision) do
    [
      late_data?: true,
      backfill_lifecycle_event_type: event_type(decision),
      validity_state: validity_state(decision),
      record_current_values?: record_current_values?(decision),
      refresh_latest_value?: refresh_latest_value?(decision),
      authority: authority(decision, %{})
    ]
  end

  defp metadata(decision) do
    %{
      "late_data_policy_decision" => Atom.to_string(decision),
      "late_data_projection_effect" => projection_effect(decision)
    }
  end

  defp validity_state(:accept), do: :canonical
  defp validity_state(:reject), do: :advisory

  defp record_current_values?(decision),
    do: record_current_values?(decision, :sample_execution)

  defp record_current_values?(:accept, :sample_execution), do: true
  defp record_current_values?(_decision, _execution_mode), do: false

  defp refresh_latest_value?(decision),
    do: refresh_latest_value?(decision, :sample_execution)

  defp refresh_latest_value?(:accept, :sample_execution), do: true
  defp refresh_latest_value?(_decision, _execution_mode), do: false

  defp projection_effect(decision), do: projection_effect(decision, :sample_execution)
  defp projection_effect(_decision, :event_only), do: "audit_event_only"

  defp projection_effect(:accept, :sample_execution),
    do: "canonical_history_and_current_projection"

  defp projection_effect(:reject, :sample_execution), do: "advisory_history_only"

  defp normalize_decision(decision) when decision in @decisions, do: {:ok, decision}

  defp normalize_decision(decision) when is_binary(decision) do
    decision
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> case do
      value when value in ["accept", "accepted", "late_data_accepted"] -> {:ok, :accept}
      value when value in ["reject", "rejected", "late_data_rejected"] -> {:ok, :reject}
      _unsupported -> {:error, {:unsupported_late_data_policy_decision, decision}}
    end
  end

  defp normalize_decision(decision),
    do: {:error, {:unsupported_late_data_policy_decision, decision}}

  defp require_context(attrs) do
    [:organization_id, :mission_id, :backfill_run_id, :data_source_id, :binding_id]
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

  defp optional_datetime_attr(attrs, field) do
    case get_attr(attrs, field) do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      %DateTime{} = datetime ->
        {:ok, datetime}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, reason} -> {:error, {:invalid_datetime_field, field, value, reason}}
        end

      value ->
        {:error, {:invalid_datetime_field, field, value}}
    end
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp compact_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
