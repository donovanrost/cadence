defmodule Cadence.Applications.PacketBindingResource do
  @moduledoc "A selected, version-pinned resource within one application packet binding."

  alias Cadence.Ids

  @type resource_kind :: :whole_packet | :field | :binary_region
  @type role :: :primary | :context

  @type t :: %__MODULE__{
          packet_binding_resource_id: binary(),
          resource_id: binary(),
          resource_kind: resource_kind(),
          path: binary() | nil,
          data_type: atom() | nil,
          offset_bits: non_neg_integer() | nil,
          size_bits: pos_integer() | nil,
          role: role(),
          metadata: map()
        }

  @enforce_keys [:packet_binding_resource_id, :resource_id, :resource_kind, :role]
  defstruct [
    :packet_binding_resource_id,
    :resource_id,
    :resource_kind,
    :path,
    :data_type,
    :offset_bits,
    :size_bits,
    :role,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      packet_binding_resource_id:
        value(attrs, :packet_binding_resource_id) || Ids.new("packet_binding_resource"),
      resource_id: required(attrs, :resource_id),
      resource_kind: attrs |> required(:resource_kind) |> normalize_resource_kind(),
      path: value(attrs, :path),
      data_type: attrs |> value(:data_type) |> normalize_optional_atom(),
      offset_bits: value(attrs, :offset_bits),
      size_bits: value(attrs, :size_bits),
      role: attrs |> value(:role, :primary) |> normalize_role(),
      metadata: value(attrs, :metadata, %{})
    }
  end

  defp normalize_resource_kind(:whole_packet), do: :whole_packet
  defp normalize_resource_kind("whole_packet"), do: :whole_packet
  defp normalize_resource_kind(:field), do: :field
  defp normalize_resource_kind("field"), do: :field
  defp normalize_resource_kind(:binary_region), do: :binary_region
  defp normalize_resource_kind("binary_region"), do: :binary_region
  defp normalize_resource_kind(other), do: other

  defp normalize_role(:primary), do: :primary
  defp normalize_role("primary"), do: :primary
  defp normalize_role(:context), do: :context
  defp normalize_role("context"), do: :context
  defp normalize_role(other), do: other

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value) when is_atom(value), do: value

  defp normalize_optional_atom(value) when is_binary(value) do
    case value do
      "uint" -> :uint
      "int" -> :int
      "float" -> :float
      "bool" -> :bool
      "binary" -> :binary
      _other -> value
    end
  end

  defp required(attrs, key), do: value(attrs, key) || raise(KeyError, key: key, term: attrs)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
