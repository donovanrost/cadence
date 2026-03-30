defmodule Cadence.Telemetry.PacketDefinition do
  @moduledoc """
  Governed telemetry packet definition used by the definition-bound telemetry
  handler.
  """

  alias Cadence.Ids
  alias Cadence.Telemetry.FieldDefinition

  @type t :: %__MODULE__{
          packet_definition_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          packet_name: binary(),
          apid: non_neg_integer(),
          version: pos_integer(),
          fields: [FieldDefinition.t()]
        }

  defstruct [
    :packet_definition_id,
    :organization_id,
    :mission_id,
    :packet_name,
    :apid,
    :version,
    fields: []
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    fields =
      attrs
      |> Map.get(:fields, [])
      |> Enum.map(fn
        %FieldDefinition{} = field -> field
        field_attrs -> FieldDefinition.new(field_attrs)
      end)

    %__MODULE__{
      packet_definition_id: Map.get(attrs, :packet_definition_id, Ids.new("packet_def")),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      packet_name: Map.fetch!(attrs, :packet_name),
      apid: Map.fetch!(attrs, :apid),
      version: Map.get(attrs, :version, 1),
      fields: fields
    }
  end
end
