defmodule Cadence.Catalog.Command.Definition do
  @moduledoc """
  Canonical command definition derived from one imported command catalog.
  """

  alias Cadence.Catalog.Command.{
    Argument,
    EncodingLayout,
    Normalize,
    OperationalMetadata,
    Provenance,
    StateEffect,
    TransmissionConstraint,
    Verifier
  }

  alias Cadence.Catalog.Ids

  @type t :: %__MODULE__{
          command_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          display_name: binary() | nil,
          description: binary() | nil,
          short_description: binary() | nil,
          abstract: boolean(),
          base_command_id: binary() | nil,
          encoding_layout_id: binary() | nil,
          argument_ids: [binary()],
          default_argument_values: map(),
          fixed_argument_values: map(),
          state_effects: [StateEffect.t()],
          transmission_constraints: [TransmissionConstraint.t()],
          verifiers: [Verifier.t()],
          operational_metadata: OperationalMetadata.t() | nil,
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :command_id,
    :snapshot_id,
    :name,
    :display_name,
    :description,
    :short_description,
    :base_command_id,
    :encoding_layout_id,
    :operational_metadata,
    :provenance,
    abstract: false,
    argument_ids: [],
    default_argument_values: %{},
    fixed_argument_values: %{},
    state_effects: [],
    transmission_constraints: [],
    verifiers: [],
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_id: Normalize.get(attrs, :command_id, Ids.new("command_definition")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      display_name: Normalize.get(attrs, :display_name),
      description: Normalize.get(attrs, :description),
      short_description: Normalize.get(attrs, :short_description),
      abstract: Normalize.get(attrs, :abstract, false),
      base_command_id: Normalize.get(attrs, :base_command_id),
      encoding_layout_id: layout_ref(Normalize.get(attrs, :encoding_layout_ref)),
      argument_ids: argument_ids(attrs),
      default_argument_values: map_value(Normalize.get(attrs, :default_argument_values, %{})),
      fixed_argument_values: map_value(Normalize.get(attrs, :fixed_argument_values, %{})),
      state_effects: Normalize.nested_list(attrs, :state_effects, StateEffect),
      transmission_constraints:
        Normalize.nested_list(attrs, :transmission_constraints, TransmissionConstraint),
      verifiers: Normalize.nested_list(attrs, :verifiers, Verifier),
      operational_metadata: Normalize.nested(attrs, :operational_metadata, OperationalMetadata),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp argument_ids(attrs) do
    attrs
    |> Normalize.get(:arguments, Normalize.get(attrs, :argument_ids, []))
    |> Enum.reduce([], fn
      %Argument{argument_id: argument_id}, acc -> acc ++ [argument_id]
      argument_id, acc when is_binary(argument_id) -> acc ++ [argument_id]
      _other, acc -> acc
    end)
  end

  defp layout_ref(%EncodingLayout{layout_id: layout_id}), do: layout_id
  defp layout_ref(layout_id) when is_binary(layout_id), do: layout_id
  defp layout_ref(_other), do: nil

  defp map_value(value) when is_map(value), do: value
  defp map_value(_other), do: %{}
end
