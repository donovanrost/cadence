defmodule Cadence.Commanding.VerifierEvaluation do
  @moduledoc """
  Pure command-verifier evaluation for telemetry samples and transport signals.

  This module owns input ordering, delay and timeout handling, subject
  normalization, and comparison, range, and compound criteria matching.
  """

  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Commanding.CommandVerifierInstance
  alias Cadence.Telemetry.Sample

  @spec evaluate_samples(CommandVerifierInstance.t(), [Sample.t()]) ::
          CommandVerifierInstance.t() | nil
  def evaluate_samples(%CommandVerifierInstance{} = verifier_instance, telemetry_samples)
      when is_list(telemetry_samples) do
    Enum.reduce_while(telemetry_samples, nil, fn %Sample{} = sample, _acc ->
      cond do
        sample_not_ready?(sample, verifier_instance) ->
          {:cont, nil}

        timed_out_before_sample?(verifier_instance, sample) ->
          {:halt,
           %CommandVerifierInstance{
             verifier_instance
             | lifecycle_state: :timed_out,
               matched_at: verifier_instance.timeout_at || sample.receipt_time,
               failure_reason: "timed_out"
           }}

        criteria_matches?(verifier_instance.failure_criteria, sample) ->
          {:halt,
           %CommandVerifierInstance{
             verifier_instance
             | lifecycle_state: :failed,
               matched_record_kind: :telemetry_sample,
               matched_record_id: sample.sample_id,
               matched_at: sample.receipt_time,
               failure_reason: "failure_criteria_matched"
           }}

        criteria_matches?(verifier_instance.success_criteria, sample) ->
          {:halt,
           %CommandVerifierInstance{
             verifier_instance
             | lifecycle_state: :satisfied,
               matched_record_kind: :telemetry_sample,
               matched_record_id: sample.sample_id,
               matched_at: sample.receipt_time,
               failure_reason: nil
           }}

        true ->
          {:cont, nil}
      end
    end)
  end

  @spec evaluate_transport_signals(CommandVerifierInstance.t(), [map()]) ::
          CommandVerifierInstance.t() | nil
  def evaluate_transport_signals(
        %CommandVerifierInstance{} = verifier_instance,
        transport_signals
      )
      when is_list(transport_signals) do
    Enum.reduce_while(transport_signals, nil, fn transport_signal, _acc ->
      cond do
        transport_signal_phase_mismatch?(transport_signal, verifier_instance) ->
          {:cont, nil}

        transport_signal_not_ready?(transport_signal, verifier_instance) ->
          {:cont, nil}

        timed_out_before_transport_signal?(verifier_instance, transport_signal) ->
          {:halt,
           %CommandVerifierInstance{
             verifier_instance
             | lifecycle_state: :timed_out,
               matched_at: verifier_instance.timeout_at || transport_signal.occurred_at,
               failure_reason: "timed_out"
           }}

        criteria_matches?(verifier_instance.failure_criteria, transport_signal) ->
          {:halt,
           %CommandVerifierInstance{
             verifier_instance
             | lifecycle_state: :failed,
               matched_record_kind: transport_signal.matched_record_kind,
               matched_record_id: transport_signal.matched_record_id,
               matched_at: transport_signal.occurred_at,
               failure_reason: "failure_criteria_matched"
           }}

        criteria_matches?(verifier_instance.success_criteria, transport_signal) ->
          {:halt,
           %CommandVerifierInstance{
             verifier_instance
             | lifecycle_state: :satisfied,
               matched_record_kind: transport_signal.matched_record_kind,
               matched_record_id: transport_signal.matched_record_id,
               matched_at: transport_signal.occurred_at,
               failure_reason: nil
           }}

        true ->
          {:cont, nil}
      end
    end)
  end

  @spec sample_sort_key(Sample.t()) :: DateTime.t() | nil
  def sample_sort_key(%Sample{} = sample), do: sample.receipt_time || sample.generation_time

  @spec transport_signal_sort_key(map()) :: {integer(), term()}
  def transport_signal_sort_key(%{
        occurred_at: %DateTime{} = occurred_at,
        matched_record_id: matched_record_id
      }),
      do: {DateTime.to_unix(occurred_at, :microsecond), matched_record_id}

  defp criteria_matches?(nil, _input), do: false

  defp criteria_matches?(
         %MatchCriteria{criteria_type: :comparison} = criteria,
         %Sample{} = sample
       ) do
    case sample_subject_value(criteria, sample) do
      {:ok, subject_value} -> compare_values(subject_value, criteria.comparison, criteria.value)
      :error -> false
    end
  end

  defp criteria_matches?(%MatchCriteria{criteria_type: :range} = criteria, %Sample{} = sample) do
    case sample_subject_value(criteria, sample) do
      {:ok, subject_value} ->
        range_matches?(subject_value, criteria.range_min, criteria.range_max)

      :error ->
        false
    end
  end

  defp criteria_matches?(
         %MatchCriteria{criteria_type: :compound, operator: :and} = criteria,
         %Sample{} = sample
       ) do
    Enum.all?(criteria.conditions, &criteria_matches?(&1, sample))
  end

  defp criteria_matches?(
         %MatchCriteria{criteria_type: :compound, operator: :or} = criteria,
         %Sample{} = sample
       ) do
    Enum.any?(criteria.conditions, &criteria_matches?(&1, sample))
  end

  defp criteria_matches?(
         %MatchCriteria{criteria_type: :comparison} = criteria,
         %{input_kind: :transport} = transport_signal
       ) do
    case transport_signal_subject_value(criteria, transport_signal) do
      {:ok, subject_value} -> compare_values(subject_value, criteria.comparison, criteria.value)
      :error -> false
    end
  end

  defp criteria_matches?(
         %MatchCriteria{criteria_type: :range} = criteria,
         %{input_kind: :transport} = transport_signal
       ) do
    case transport_signal_subject_value(criteria, transport_signal) do
      {:ok, subject_value} ->
        range_matches?(subject_value, criteria.range_min, criteria.range_max)

      :error ->
        false
    end
  end

  defp criteria_matches?(
         %MatchCriteria{criteria_type: :compound, operator: :and} = criteria,
         %{input_kind: :transport} = transport_signal
       ) do
    Enum.all?(criteria.conditions, &criteria_matches?(&1, transport_signal))
  end

  defp criteria_matches?(
         %MatchCriteria{criteria_type: :compound, operator: :or} = criteria,
         %{input_kind: :transport} = transport_signal
       ) do
    Enum.any?(criteria.conditions, &criteria_matches?(&1, transport_signal))
  end

  defp criteria_matches?(%MatchCriteria{}, _input), do: false

  defp sample_subject_value(%MatchCriteria{} = criteria, %Sample{} = sample) do
    if sample_matches_subject_ref?(criteria.subject_ref, sample) do
      value = if criteria.use_calibrated, do: sample.engineering_value, else: sample.raw_value
      {:ok, value}
    else
      :error
    end
  end

  defp transport_signal_subject_value(
         %MatchCriteria{} = criteria,
         %{input_kind: :transport, subject_values: subject_values}
       )
       when is_map(subject_values) do
    case normalize_transport_subject_ref(criteria.subject_ref) do
      nil -> :error
      subject_ref -> Map.fetch(subject_values, subject_ref)
    end
  end

  defp sample_matches_subject_ref?(nil, _sample), do: false

  defp sample_matches_subject_ref?(subject_ref, %Sample{} = sample) when is_binary(subject_ref) do
    normalized_ref = normalize_subject_ref(subject_ref)
    normalized_point_id = normalize_subject_ref(sample.point_id)
    normalized_point_name = normalize_subject_ref(sample.point_name)

    normalized_ref in [normalized_point_id, normalized_point_name]
  end

  defp normalize_subject_ref(subject_ref) when is_binary(subject_ref) do
    subject_ref
    |> String.trim()
    |> String.trim_leading("telemetry:")
  end

  defp normalize_transport_subject_ref(nil), do: nil

  defp normalize_transport_subject_ref(subject_ref) when is_binary(subject_ref) do
    normalized_ref = String.trim(subject_ref)

    if String.starts_with?(normalized_ref, "transport:") do
      normalized_ref
    else
      "transport:" <> normalized_ref
    end
  end

  defp compare_values(_subject_value, nil, _expected_value), do: false
  defp compare_values(subject_value, :equal, expected_value), do: subject_value == expected_value

  defp compare_values(subject_value, :not_equal, expected_value),
    do: subject_value != expected_value

  defp compare_values(subject_value, comparison, expected_value)
       when comparison in [:greater, :less, :greater_equal, :less_equal] do
    with {:ok, subject_number} <- numeric_term(subject_value),
         {:ok, expected_number} <- numeric_term(expected_value) do
      case comparison do
        :greater -> subject_number > expected_number
        :less -> subject_number < expected_number
        :greater_equal -> subject_number >= expected_number
        :less_equal -> subject_number <= expected_number
      end
    else
      :error -> false
    end
  end

  defp compare_values(subject_value, :in_range, expected_value) when is_map(expected_value) do
    range_matches?(subject_value, Map.get(expected_value, "min"), Map.get(expected_value, "max"))
  end

  defp compare_values(subject_value, :not_in_range, expected_value) when is_map(expected_value) do
    not range_matches?(
      subject_value,
      Map.get(expected_value, "min"),
      Map.get(expected_value, "max")
    )
  end

  defp compare_values(_subject_value, _comparison, _expected_value), do: false

  defp range_matches?(subject_value, range_min, range_max) do
    with {:ok, subject_number} <- numeric_term(subject_value),
         {:ok, min_number} <- numeric_term(range_min),
         {:ok, max_number} <- numeric_term(range_max) do
      subject_number >= min_number and subject_number <= max_number
    else
      :error -> false
    end
  end

  defp numeric_term(value) when is_integer(value), do: {:ok, value}
  defp numeric_term(value) when is_float(value), do: {:ok, value}
  defp numeric_term(_value), do: :error

  defp sample_not_ready?(%Sample{} = sample, %CommandVerifierInstance{} = verifier_instance) do
    case verifier_instance.delay_until do
      %DateTime{} = delay_until -> DateTime.compare(sample.receipt_time, delay_until) == :lt
      nil -> false
    end
  end

  defp transport_signal_not_ready?(
         %{input_kind: :transport, occurred_at: occurred_at},
         %CommandVerifierInstance{} = verifier_instance
       )
       when is_struct(occurred_at, DateTime) do
    case verifier_instance.delay_until do
      %DateTime{} = delay_until -> DateTime.compare(occurred_at, delay_until) == :lt
      nil -> false
    end
  end

  defp timed_out_before_sample?(
         %CommandVerifierInstance{} = verifier_instance,
         %Sample{} = sample
       ) do
    case verifier_instance.timeout_at do
      %DateTime{} = timeout_at -> DateTime.compare(sample.receipt_time, timeout_at) == :gt
      nil -> false
    end
  end

  defp timed_out_before_transport_signal?(
         %CommandVerifierInstance{} = verifier_instance,
         %{input_kind: :transport, occurred_at: occurred_at}
       )
       when is_struct(occurred_at, DateTime) do
    case verifier_instance.timeout_at do
      %DateTime{} = timeout_at -> DateTime.compare(occurred_at, timeout_at) == :gt
      nil -> false
    end
  end

  defp transport_signal_phase_mismatch?(
         %{input_kind: :transport, phase: signal_phase},
         %CommandVerifierInstance{} = verifier_instance
       ) do
    signal_phase != verifier_instance.phase
  end
end
