defmodule CadenceSimulator.Provider.FaultProfile do
  @moduledoc "Validated scenario and run-scoped provider fault controls."

  alias CadenceSimulator.Provider.Contract

  @rate_fields [
    "scheduling_rejection_rate",
    "acquisition_failure_rate",
    "early_termination_rate",
    "packet_loss_rate"
  ]
  @count_fields [
    "contact_response_loss_after_commit_count",
    "contact_modification_response_loss_after_commit_count",
    "event_omission_count",
    "event_duplication_count",
    "event_delay_poll_count",
    "event_reordering_count",
    "event_identity_collision_count"
  ]
  @duration_fields ["latency_ms", "jitter_ms"]
  @boolean_fields ["provider_outage"]
  @fields @rate_fields ++ @count_fields ++ @duration_fields ++ @boolean_fields

  @defaults %{
    "scheduling_rejection_rate" => 0.0,
    "acquisition_failure_rate" => 0.0,
    "early_termination_rate" => 0.0,
    "packet_loss_rate" => 0.0,
    "contact_response_loss_after_commit_count" => 0,
    "contact_modification_response_loss_after_commit_count" => 0,
    "event_omission_count" => 0,
    "event_duplication_count" => 0,
    "event_delay_poll_count" => 0,
    "event_reordering_count" => 0,
    "event_identity_collision_count" => 0,
    "latency_ms" => 0,
    "jitter_ms" => 0,
    "provider_outage" => false
  }

  @spec defaults() :: map()
  def defaults, do: @defaults

  @spec normalize(term()) :: {:ok, map()} | {:error, {:invalid, binary()}}
  def normalize(profile) when is_map(profile) do
    profile = Contract.sanitize(profile)
    unknown = Map.keys(profile) -- @fields

    with :ok <- ensure_known(unknown),
         merged = Map.merge(@defaults, profile),
         :ok <- validate_rates(merged),
         :ok <- validate_nonnegative_integers(merged, @count_fields ++ @duration_fields),
         :ok <- validate_booleans(merged) do
      {:ok, merged}
    end
  end

  def normalize(_profile), do: {:error, {:invalid, "fault_profile must be an object"}}

  @spec merge(map(), term()) :: {:ok, map()} | {:error, {:invalid, binary()}}
  def merge(current, updates) when is_map(current) and is_map(updates) do
    normalize(Map.merge(current, updates))
  end

  def merge(_current, _updates),
    do: {:error, {:invalid, "fault_profile must be an object"}}

  defp ensure_known([]), do: :ok

  defp ensure_known([field | _rest]),
    do: {:error, {:invalid, "unsupported fault_profile field: #{field}"}}

  defp validate_rates(profile) do
    case Enum.find(@rate_fields, fn field ->
           value = profile[field]
           not (is_number(value) and value >= 0 and value <= 1)
         end) do
      nil -> :ok
      field -> invalid_field(field)
    end
  end

  defp validate_nonnegative_integers(profile, fields) do
    case Enum.find(fields, fn field ->
           value = profile[field]
           not (is_integer(value) and value >= 0)
         end) do
      nil -> :ok
      field -> invalid_field(field)
    end
  end

  defp validate_booleans(profile) do
    case Enum.find(@boolean_fields, &(not is_boolean(profile[&1]))) do
      nil -> :ok
      field -> invalid_field(field)
    end
  end

  defp invalid_field(field), do: {:error, {:invalid, "fault_profile.#{field} is invalid"}}
end
