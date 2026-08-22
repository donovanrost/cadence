defmodule Cadence.Applications.PacketInputDefinition do
  @moduledoc """
  Versioned declaration of packet-model resources accepted by one capability.

  The declaration is host-owned validation and presentation metadata. It never
  contains executable callbacks or application-supplied rendering behavior.
  """

  @type resource_kind :: :whole_packet | :field | :binary_region
  @type selection_mode :: :whole_packet | :compatible_fields | :explicit_fields
  @type delivery :: :packet_record | :decoded_fields | :field_views
  @type failure_policy :: :isolated

  @type t :: %__MODULE__{
          input_id: binary(),
          version: pos_integer(),
          capability_family_key: atom(),
          accepted_resource_kinds: [resource_kind()],
          accepted_data_types: [atom()],
          selection_mode: selection_mode(),
          min_selected: non_neg_integer(),
          max_selected: pos_integer(),
          delivery: delivery(),
          failure_policy: failure_policy()
        }

  @enforce_keys [
    :input_id,
    :version,
    :capability_family_key,
    :accepted_resource_kinds,
    :selection_mode,
    :min_selected,
    :max_selected,
    :delivery,
    :failure_policy
  ]

  defstruct [
    :input_id,
    :version,
    :capability_family_key,
    :selection_mode,
    :min_selected,
    :max_selected,
    :delivery,
    :failure_policy,
    accepted_resource_kinds: [],
    accepted_data_types: []
  ]

  @resource_kinds [:whole_packet, :field, :binary_region]
  @selection_modes [:whole_packet, :compatible_fields, :explicit_fields]
  @deliveries [:packet_record, :decoded_fields, :field_views]
  @failure_policies [:isolated]
  @max_resources 4_096

  @spec validate(t()) :: :ok | {:error, :invalid_packet_input_definition}
  def validate(%__MODULE__{} = definition) do
    if valid_identity?(definition) and valid_resource_contract?(definition) and
         valid_delivery_contract?(definition) do
      :ok
    else
      {:error, :invalid_packet_input_definition}
    end
  end

  def validate(_definition), do: {:error, :invalid_packet_input_definition}

  defp valid_identity?(definition),
    do:
      valid_text?(definition.input_id) and positive_integer?(definition.version) and
        valid_family_key?(definition.capability_family_key)

  defp valid_resource_contract?(definition),
    do:
      valid_atoms?(definition.accepted_resource_kinds, @resource_kinds) and
        definition.accepted_resource_kinds != [] and
        valid_atoms?(definition.accepted_data_types) and
        definition.selection_mode in @selection_modes and
        valid_cardinality?(definition.min_selected, definition.max_selected) and
        selection_matches_resources?(definition)

  defp valid_delivery_contract?(definition),
    do: definition.delivery in @deliveries and definition.failure_policy in @failure_policies

  defp selection_matches_resources?(%__MODULE__{selection_mode: :whole_packet} = definition),
    do: definition.accepted_resource_kinds == [:whole_packet]

  defp selection_matches_resources?(%__MODULE__{selection_mode: :compatible_fields} = definition),
    do: :field in definition.accepted_resource_kinds

  defp selection_matches_resources?(%__MODULE__{selection_mode: :explicit_fields} = definition),
    do: Enum.any?(definition.accepted_resource_kinds, &(&1 in [:field, :binary_region]))

  defp valid_cardinality?(minimum, maximum) do
    is_integer(minimum) and minimum >= 0 and positive_integer?(maximum) and
      minimum <= maximum and maximum <= @max_resources
  end

  defp valid_family_key?(value), do: is_atom(value) and not is_nil(value)

  defp valid_atoms?(values, allowed \\ nil)

  defp valid_atoms?(values, allowed) when is_list(values) do
    Enum.all?(values, fn value ->
      is_atom(value) and not is_nil(value) and (is_nil(allowed) or value in allowed)
    end) and length(Enum.uniq(values)) == length(values)
  end

  defp valid_atoms?(_values, _allowed), do: false
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp valid_text?(value), do: is_binary(value) and value != ""
end
