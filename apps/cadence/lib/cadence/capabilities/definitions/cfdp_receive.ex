defmodule Cadence.Capabilities.Definitions.CFDPReceive do
  @moduledoc false

  alias Cadence.Capabilities.{Descriptor, ValidationContext}

  @default_check_limit 2
  @default_check_interval_ms 5_000
  @default_max_active_transactions 32
  @default_max_in_memory_file_octets 1_048_576
  @maximum_active_transactions 1_024
  @maximum_in_memory_file_octets 16_777_216

  @known_keys [
    :local_entity_id,
    :check_limit,
    :check_interval_ms,
    :max_active_transactions,
    :max_in_memory_file_octets,
    "local_entity_id",
    "check_limit",
    "check_interval_ms",
    "max_active_transactions",
    "max_in_memory_file_octets"
  ]

  @spec descriptor() :: Descriptor.t()
  def descriptor do
    Descriptor.new(%{
      family_key: :cfdp_receive,
      version: 1,
      kind: :managed_application,
      supported_scopes: [:source_endpoint],
      input_stages: [:space_packet],
      partition_affinity: :source_endpoint,
      config_schema: nil,
      emitted_record_kinds: [:cfdp_transaction_event],
      emitted_action_kinds: [:schedule_timer, :cancel_timer],
      replay_mode: :deterministic,
      state_mode: :stateful
    })
  end

  @spec validate_config(term(), ValidationContext.t()) :: :ok | {:error, term()}
  def validate_config(configuration, %ValidationContext{}) do
    case normalize_config(configuration) do
      {:ok, _normalized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec normalize_config(term()) :: {:ok, map()} | {:error, term()}
  def normalize_config(configuration) when is_map(configuration) do
    unknown_keys = Map.keys(configuration) -- @known_keys

    if unknown_keys == [] do
      normalized = %{
        local_entity_id: get(configuration, :local_entity_id),
        check_limit: get(configuration, :check_limit, @default_check_limit),
        check_interval_ms: get(configuration, :check_interval_ms, @default_check_interval_ms),
        max_active_transactions:
          get(configuration, :max_active_transactions, @default_max_active_transactions),
        max_in_memory_file_octets:
          get(
            configuration,
            :max_in_memory_file_octets,
            @default_max_in_memory_file_octets
          )
      }

      with :ok <- identifier(normalized.local_entity_id, :local_entity_id),
           :ok <- positive(normalized.check_limit, :check_limit),
           :ok <- positive(normalized.check_interval_ms, :check_interval_ms),
           :ok <-
             range(
               normalized.max_active_transactions,
               1,
               @maximum_active_transactions,
               :max_active_transactions
             ),
           :ok <-
             range(
               normalized.max_in_memory_file_octets,
               1,
               @maximum_in_memory_file_octets,
               :max_in_memory_file_octets
             ) do
        {:ok, normalized}
      end
    else
      {:error, {:unknown_cfdp_receive_configuration_keys, unknown_keys}}
    end
  end

  def normalize_config(configuration),
    do: {:error, {:unsupported_cfdp_receive_configuration, configuration}}

  defp get(configuration, key, default \\ nil) do
    Map.get(configuration, key, Map.get(configuration, Atom.to_string(key), default))
  end

  defp identifier(value, _field)
       when is_integer(value) and value >= 0 and value <= 0xFFFFFFFFFFFFFFFF,
       do: :ok

  defp identifier(value, field), do: {:error, {:invalid_field, field, value}}

  defp positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
