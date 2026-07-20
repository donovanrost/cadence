defmodule Cadence.Catalog.Command.Compiler.RuntimeDefinition do
  @moduledoc """
  Compiled runtime-facing command definition used for future validation and
  encoding.
  """

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, EncodingStep}

  @type layout_kind :: :binary_container | :space_packet | :service_data_unit | :raw_payload
  @type byte_order :: :big_endian | :little_endian

  @type t :: %__MODULE__{
          command_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          display_name: binary() | nil,
          description: binary() | nil,
          layout_id: binary(),
          layout_kind: layout_kind(),
          byte_order: byte_order(),
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term() | nil,
          opcode_size_bits: pos_integer() | nil,
          size_bits: pos_integer() | nil,
          max_size_bits: pos_integer() | nil,
          argument_specs: [ArgumentSpec.t()],
          encoding_steps: [EncodingStep.t()],
          default_argument_values: map(),
          fixed_argument_values: map(),
          metadata: map()
        }

  defstruct [
    :command_id,
    :snapshot_id,
    :name,
    :display_name,
    :description,
    :layout_id,
    :layout_kind,
    :byte_order,
    :apid,
    :service_type,
    :service_subtype,
    :opcode,
    :opcode_size_bits,
    :size_bits,
    :max_size_bits,
    argument_specs: [],
    encoding_steps: [],
    default_argument_values: %{},
    fixed_argument_values: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_id: Map.fetch!(attrs, :command_id),
      snapshot_id: Map.fetch!(attrs, :snapshot_id),
      name: Map.fetch!(attrs, :name),
      display_name: Map.get(attrs, :display_name),
      description: Map.get(attrs, :description),
      layout_id: Map.fetch!(attrs, :layout_id),
      layout_kind: Map.fetch!(attrs, :layout_kind),
      byte_order: Map.fetch!(attrs, :byte_order),
      apid: Map.get(attrs, :apid),
      service_type: Map.get(attrs, :service_type),
      service_subtype: Map.get(attrs, :service_subtype),
      opcode: Map.get(attrs, :opcode),
      opcode_size_bits: Map.get(attrs, :opcode_size_bits),
      size_bits: Map.get(attrs, :size_bits),
      max_size_bits: Map.get(attrs, :max_size_bits),
      argument_specs: Map.get(attrs, :argument_specs, []),
      encoding_steps: Map.get(attrs, :encoding_steps, []),
      default_argument_values: Map.get(attrs, :default_argument_values, %{}),
      fixed_argument_values: Map.get(attrs, :fixed_argument_values, %{}),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
