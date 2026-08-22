defmodule Cadence.Applications.SurfaceElements.PacketBindingResource do
  @moduledoc "Host-rendered packet resource row within a Packet Bindings group."

  @type compatibility :: :compatible | :incompatible

  @type t :: %__MODULE__{
          id: binary(),
          resource_id: binary(),
          path: binary(),
          resource_kind: :whole_packet | :field | :binary_region,
          data_type: atom() | nil,
          size_bits: pos_integer() | nil,
          compatibility: compatibility(),
          reason: binary() | nil,
          selected: boolean(),
          role: :primary | :context,
          consumers: [binary()]
        }

  @enforce_keys [
    :id,
    :resource_id,
    :path,
    :resource_kind,
    :compatibility,
    :selected,
    :role
  ]

  defstruct [
    :id,
    :resource_id,
    :path,
    :resource_kind,
    :data_type,
    :size_bits,
    :compatibility,
    :reason,
    :selected,
    :role,
    consumers: []
  ]

  @resource_kinds [:whole_packet, :field, :binary_region]
  @data_types [:uint, :int, :float, :bool, :binary]

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_packet_binding_resource}
  def validate(%__MODULE__{} = resource) do
    if valid_identity?(resource) and valid_type?(resource) and valid_state?(resource) and
         valid_consumers?(resource.consumers) do
      :ok
    else
      {:error, :invalid_application_surface_packet_binding_resource}
    end
  end

  def validate(_resource),
    do: {:error, :invalid_application_surface_packet_binding_resource}

  defp valid_identity?(resource),
    do:
      valid_text?(resource.id) and valid_text?(resource.resource_id) and
        valid_text?(resource.path)

  defp valid_type?(resource),
    do:
      resource.resource_kind in @resource_kinds and optional_data_type?(resource.data_type) and
        optional_size?(resource.size_bits)

  defp valid_state?(resource),
    do:
      resource.compatibility in [:compatible, :incompatible] and
        optional_text?(resource.reason) and is_boolean(resource.selected) and
        resource.role in [:primary, :context]

  defp optional_data_type?(nil), do: true
  defp optional_data_type?(data_type), do: data_type in @data_types
  defp optional_size?(nil), do: true
  defp optional_size?(size_bits), do: positive_integer?(size_bits)

  defp valid_consumers?(consumers) when is_list(consumers) do
    length(consumers) <= 16 and Enum.all?(consumers, &valid_text?/1) and
      length(Enum.uniq(consumers)) == length(consumers)
  end

  defp valid_consumers?(_consumers), do: false
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
