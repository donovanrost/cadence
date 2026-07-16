defmodule Cadence.GroundNetworks.DeliveryPolicy do
  @moduledoc "Validated mission-scoped policy for provider Contact changes."

  alias Cadence.GroundNetworks.Validation

  @modes [:approval_required, :bounded_automatic]
  @deadline_behaviors [:retain_last_accepted, :cancel_if_actionable]
  @approval_categories ~w(schedule resource capacity cost cancellation counteroffer)
  @known_fields ~w(
    version mode maximum_earlier_start_shift_seconds maximum_later_start_shift_seconds
    maximum_earlier_end_shift_seconds maximum_later_end_shift_seconds
    minimum_retained_duration_seconds minimum_retained_estimated_capacity_bytes
    approved_station_substitutions approved_equivalent_resource_substitutions
    maximum_cost_delta changes_always_requiring_approval deadline_behavior
    allow_automatic_execution_revision extensions
  )

  @type t :: %__MODULE__{
          version: pos_integer(),
          mode: atom(),
          maximum_earlier_start_shift_seconds: non_neg_integer(),
          maximum_later_start_shift_seconds: non_neg_integer(),
          maximum_earlier_end_shift_seconds: non_neg_integer(),
          maximum_later_end_shift_seconds: non_neg_integer(),
          minimum_retained_duration_seconds: non_neg_integer() | nil,
          minimum_retained_estimated_capacity_bytes: non_neg_integer() | nil,
          approved_station_substitutions: [binary()],
          approved_equivalent_resource_substitutions: [binary()],
          maximum_cost_delta: number() | nil,
          changes_always_requiring_approval: [binary()],
          deadline_behavior: atom(),
          allow_automatic_execution_revision: boolean(),
          extensions: map()
        }

  defstruct version: 1,
            mode: :approval_required,
            maximum_earlier_start_shift_seconds: 0,
            maximum_later_start_shift_seconds: 0,
            maximum_earlier_end_shift_seconds: 0,
            maximum_later_end_shift_seconds: 0,
            minimum_retained_duration_seconds: nil,
            minimum_retained_estimated_capacity_bytes: nil,
            approved_station_substitutions: [],
            approved_equivalent_resource_substitutions: [],
            maximum_cost_delta: nil,
            changes_always_requiring_approval: [],
            deadline_behavior: :retain_last_accepted,
            allow_automatic_execution_revision: true,
            extensions: %{}

  @spec normalize(map()) :: {:ok, t()} | {:error, term()}
  def normalize(document) when is_map(document) do
    document = Validation.sanitize(document)

    with :ok <- reject_unknown(document),
         {:ok, version} <- positive_integer(document, "version", 1),
         {:ok, mode} <- member(document, "mode", @modes, :approval_required),
         {:ok, earlier_start} <- nonnegative(document, "maximum_earlier_start_shift_seconds", 0),
         {:ok, later_start} <- nonnegative(document, "maximum_later_start_shift_seconds", 0),
         {:ok, earlier_end} <- nonnegative(document, "maximum_earlier_end_shift_seconds", 0),
         {:ok, later_end} <- nonnegative(document, "maximum_later_end_shift_seconds", 0),
         {:ok, minimum_duration} <-
           optional_nonnegative(document, "minimum_retained_duration_seconds"),
         {:ok, minimum_capacity} <-
           optional_nonnegative(document, "minimum_retained_estimated_capacity_bytes"),
         {:ok, approved_stations} <- string_list(document, "approved_station_substitutions"),
         {:ok, approved_resources} <-
           string_list(document, "approved_equivalent_resource_substitutions"),
         {:ok, maximum_cost_delta} <- optional_number(document, "maximum_cost_delta"),
         {:ok, always_approval} <- string_list(document, "changes_always_requiring_approval"),
         :ok <- validate_categories(always_approval),
         {:ok, deadline_behavior} <-
           member(document, "deadline_behavior", @deadline_behaviors, :retain_last_accepted),
         {:ok, auto_revision} <-
           boolean(document, "allow_automatic_execution_revision", true),
         {:ok, extensions} <- object(document, "extensions") do
      {:ok,
       %__MODULE__{
         version: version,
         mode: mode,
         maximum_earlier_start_shift_seconds: earlier_start,
         maximum_later_start_shift_seconds: later_start,
         maximum_earlier_end_shift_seconds: earlier_end,
         maximum_later_end_shift_seconds: later_end,
         minimum_retained_duration_seconds: minimum_duration,
         minimum_retained_estimated_capacity_bytes: minimum_capacity,
         approved_station_substitutions: approved_stations,
         approved_equivalent_resource_substitutions: approved_resources,
         maximum_cost_delta: maximum_cost_delta,
         changes_always_requiring_approval: always_approval,
         deadline_behavior: deadline_behavior,
         allow_automatic_execution_revision: auto_revision,
         extensions: extensions
       }}
    end
  end

  def normalize(_document), do: {:error, :delivery_policy_must_be_an_object}

  @spec to_document(t()) :: map()
  def to_document(%__MODULE__{} = policy) do
    %{
      "version" => policy.version,
      "mode" => Atom.to_string(policy.mode),
      "maximum_earlier_start_shift_seconds" => policy.maximum_earlier_start_shift_seconds,
      "maximum_later_start_shift_seconds" => policy.maximum_later_start_shift_seconds,
      "maximum_earlier_end_shift_seconds" => policy.maximum_earlier_end_shift_seconds,
      "maximum_later_end_shift_seconds" => policy.maximum_later_end_shift_seconds,
      "minimum_retained_duration_seconds" => policy.minimum_retained_duration_seconds,
      "minimum_retained_estimated_capacity_bytes" =>
        policy.minimum_retained_estimated_capacity_bytes,
      "approved_station_substitutions" => policy.approved_station_substitutions,
      "approved_equivalent_resource_substitutions" =>
        policy.approved_equivalent_resource_substitutions,
      "maximum_cost_delta" => policy.maximum_cost_delta,
      "changes_always_requiring_approval" => policy.changes_always_requiring_approval,
      "deadline_behavior" => Atom.to_string(policy.deadline_behavior),
      "allow_automatic_execution_revision" => policy.allow_automatic_execution_revision,
      "extensions" => policy.extensions
    }
  end

  defp reject_unknown(document) do
    case Map.keys(document) -- @known_fields do
      [] -> :ok
      [field | _rest] -> {:error, {:unknown_delivery_policy_field, field}}
    end
  end

  defp positive_integer(document, key, default) do
    case Map.get(document, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> invalid(key)
    end
  end

  defp nonnegative(document, key, default) do
    case Map.get(document, key, default) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _value -> invalid(key)
    end
  end

  defp optional_nonnegative(document, key) do
    case Map.get(document, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _value -> invalid(key)
    end
  end

  defp optional_number(document, key) do
    case Map.get(document, key) do
      nil -> {:ok, nil}
      value when is_number(value) and value >= 0 -> {:ok, value}
      _value -> invalid(key)
    end
  end

  defp string_list(document, key) do
    case Map.get(document, key, []) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")), do: {:ok, values}, else: invalid(key)

      _value ->
        invalid(key)
    end
  end

  defp object(document, key) do
    case Map.get(document, key, %{}) do
      value when is_map(value) -> {:ok, value}
      _value -> invalid(key)
    end
  end

  defp boolean(document, key, default) do
    case Map.get(document, key, default) do
      value when is_boolean(value) -> {:ok, value}
      _value -> invalid(key)
    end
  end

  defp member(document, key, allowed, default) do
    value = Map.get(document, key, Atom.to_string(default))

    case Enum.find(allowed, &(value == &1 or value == Atom.to_string(&1))) do
      nil -> invalid(key)
      normalized -> {:ok, normalized}
    end
  end

  defp validate_categories(categories) do
    case categories -- @approval_categories do
      [] -> :ok
      [category | _rest] -> {:error, {:unknown_delivery_policy_category, category}}
    end
  end

  defp invalid(key), do: {:error, {:invalid_delivery_policy_field, key}}
end
