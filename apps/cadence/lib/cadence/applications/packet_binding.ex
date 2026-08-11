defmodule Cadence.Applications.PacketBinding do
  @moduledoc "One resolved packet or selector bound to an installed application input."

  alias Cadence.Applications.PacketBindingResource
  alias Cadence.Ids

  @type t :: %__MODULE__{
          packet_binding_id: binary(),
          source_endpoint_ref: binary() | nil,
          catalog_revision_id: binary() | nil,
          telemetry_snapshot_id: binary() | nil,
          packet_id: binary() | nil,
          packet_model_content_sha256: binary() | nil,
          packet_name: binary(),
          apid: non_neg_integer(),
          selector: map(),
          resources: [PacketBindingResource.t()],
          metadata: map()
        }

  @enforce_keys [:packet_binding_id, :packet_name, :apid]
  defstruct [
    :packet_binding_id,
    :source_endpoint_ref,
    :catalog_revision_id,
    :telemetry_snapshot_id,
    :packet_id,
    :packet_model_content_sha256,
    :packet_name,
    :apid,
    selector: %{},
    resources: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    resources =
      attrs
      |> value(:resources, [])
      |> Enum.map(fn
        %PacketBindingResource{} = resource -> resource
        resource_attrs -> PacketBindingResource.new(resource_attrs)
      end)

    %__MODULE__{
      packet_binding_id: value(attrs, :packet_binding_id) || Ids.new("packet_binding"),
      source_endpoint_ref: value(attrs, :source_endpoint_ref),
      catalog_revision_id: value(attrs, :catalog_revision_id),
      telemetry_snapshot_id: value(attrs, :telemetry_snapshot_id),
      packet_id: value(attrs, :packet_id),
      packet_model_content_sha256: value(attrs, :packet_model_content_sha256),
      packet_name: required(attrs, :packet_name),
      apid: required(attrs, :apid),
      selector: value(attrs, :selector, %{}),
      resources: resources,
      metadata: value(attrs, :metadata, %{})
    }
  end

  defp required(attrs, key), do: value(attrs, key) || raise(KeyError, key: key, term: attrs)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
