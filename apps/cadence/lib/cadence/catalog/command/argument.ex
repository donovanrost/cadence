defmodule Cadence.Catalog.Command.Argument do
  @moduledoc """
  Canonical command argument definition independent of any one binary layout.
  """

  alias Cadence.Catalog.Command.{ArgumentType, Normalize, Provenance}
  alias Cadence.Ids

  @type t :: %__MODULE__{
          argument_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          description: binary() | nil,
          argument_type_id: binary(),
          required: boolean(),
          default_value: term() | nil,
          fixed_value: term() | nil,
          display_order: integer() | nil,
          hazardous_values: [term()],
          metadata: map(),
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :argument_id,
    :snapshot_id,
    :name,
    :description,
    :argument_type_id,
    :default_value,
    :fixed_value,
    :display_order,
    :provenance,
    required: true,
    hazardous_values: [],
    metadata: %{},
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      argument_id: Normalize.get(attrs, :argument_id, Ids.new("command_argument")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      description: Normalize.get(attrs, :description),
      argument_type_id: argument_type_ref(Normalize.get(attrs, :argument_type_ref)),
      required: Normalize.get(attrs, :required, true),
      default_value: Normalize.get(attrs, :default_value),
      fixed_value: Normalize.get(attrs, :fixed_value),
      display_order: Normalize.get(attrs, :display_order),
      hazardous_values: list_value(Normalize.get(attrs, :hazardous_values, [])),
      metadata: Normalize.get(attrs, :metadata, %{}),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp argument_type_ref(%ArgumentType{argument_type_id: argument_type_id}), do: argument_type_id
  defp argument_type_ref(argument_type_id) when is_binary(argument_type_id), do: argument_type_id
  defp argument_type_ref(_other), do: nil

  defp list_value(values) when is_list(values), do: values
  defp list_value(_other), do: []
end
