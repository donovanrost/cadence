defmodule Cadence.Comms.GroundStation do
  @moduledoc """
  Mission-owned ground antenna or ground-station site used as setup context.

  A GroundStation is setup state. Runtime contact, RF lock, and connection
  state are recorded elsewhere and may reference this stable identity.

  Geometry for pass prediction (#890): `location` is the mission's own WGS84 geodetic
  latitude, longitude (degrees) and height (metres), set through the `ground_station`
  change-set kind; `provider_location` is what a provider reported in its inventory, kept
  apart so a report never overwrites the mission's value. `effective_location/1` is the
  mission's when set, else the provider's. `elevation_mask_deg` defaults to 5°.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :active | :archived
  @type location :: %{latitude_deg: float(), longitude_deg: float(), height_m: float()}
  @type provider_location :: %{
          latitude_deg: float(),
          longitude_deg: float(),
          height_m: float(),
          provider_id: binary() | nil,
          reported_at: DateTime.t() | nil
        }

  @type t :: %__MODULE__{
          ground_station_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          lifecycle_state: lifecycle_state(),
          display_name: binary(),
          code: binary() | nil,
          provider: binary() | nil,
          region: binary() | nil,
          metadata: map(),
          location: location() | nil,
          elevation_mask_deg: float(),
          provider_location: provider_location() | nil
        }

  defstruct [
    :ground_station_id,
    :organization_id,
    :mission_id,
    :lifecycle_state,
    :display_name,
    :code,
    :provider,
    :region,
    :location,
    :provider_location,
    metadata: %{},
    elevation_mask_deg: 5.0
  ]

  @default_elevation_mask_deg 5.0

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
      code: Map.get(attrs, :code, Map.get(attrs, "code")),
      provider: Map.get(attrs, :provider, Map.get(attrs, "provider")),
      region: Map.get(attrs, :region, Map.get(attrs, "region")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})),
      location: Map.get(attrs, :location),
      elevation_mask_deg: Map.get(attrs, :elevation_mask_deg) || @default_elevation_mask_deg,
      provider_location: Map.get(attrs, :provider_location)
    }
  end

  @doc """
  The location pass prediction uses, with where it came from: the mission's own when set,
  else the provider's report, else nil.
  """
  @spec effective_location(t()) ::
          %{
            latitude_deg: float(),
            longitude_deg: float(),
            height_m: float(),
            source: :mission | :provider
          }
          | nil
  def effective_location(%__MODULE__{location: %{} = location}),
    do: Map.put(location, :source, :mission)

  def effective_location(%__MODULE__{provider_location: %{} = location}),
    do:
      location
      |> Map.take([:latitude_deg, :longitude_deg, :height_m])
      |> Map.put(:source, :provider)

  def effective_location(%__MODULE__{}), do: nil

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
