defmodule Cadence.Comms.GroundStation do
  @moduledoc """
  Mission-owned ground antenna or ground-station site used as setup context.

  A GroundStation is setup state. Runtime contact, RF lock, and connection
  state are recorded elsewhere and may reference this stable identity.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :active | :archived

  @type t :: %__MODULE__{
          ground_station_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          lifecycle_state: lifecycle_state(),
          display_name: binary(),
          provider: binary() | nil,
          region: binary() | nil,
          metadata: map()
        }

  defstruct [
    :ground_station_id,
    :organization_id,
    :mission_id,
    :lifecycle_state,
    :display_name,
    :provider,
    :region,
    metadata: %{}
  ]

  @lifecycle_states [:active, :archived]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      ground_station_id:
        Map.get(
          attrs,
          :ground_station_id,
          Map.get(attrs, "ground_station_id", Ids.new("ground_station"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_atom(@lifecycle_states, :lifecycle_state),
      display_name: Map.fetch!(attrs, :display_name),
      provider: Map.get(attrs, :provider, Map.get(attrs, "provider")),
      region: Map.get(attrs, :region, Map.get(attrs, "region")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_atom(value, allowed, field) when is_atom(value) do
    if value in allowed do
      value
    else
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
    end
  end

  defp normalize_atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize_atom(value, _allowed, field) do
    raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end
end
