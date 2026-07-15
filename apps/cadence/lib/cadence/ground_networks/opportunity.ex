defmodule Cadence.GroundNetworks.Opportunity do
  @moduledoc "Validated provider opportunity proposal."

  alias Cadence.GroundNetworks.Validation

  @availability %{
    "available" => :available,
    "limited" => :limited,
    "unavailable" => :unavailable
  }

  @type t :: %__MODULE__{
          id: binary(),
          spacecraft_ref: binary(),
          ground_station_ref: binary(),
          antenna_or_service_pool_ref: binary(),
          service_profile_ref: binary(),
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          expires_at: DateTime.t(),
          availability: atom(),
          estimated_capacity: map() | nil,
          synthetic: boolean(),
          extensions: map(),
          evidence: map()
        }

  defstruct [
    :id,
    :spacecraft_ref,
    :ground_station_ref,
    :antenna_or_service_pool_ref,
    :service_profile_ref,
    :starts_at,
    :ends_at,
    :expires_at,
    :availability,
    :estimated_capacity,
    synthetic: false,
    extensions: %{},
    evidence: %{}
  ]

  @spec from_external(map()) :: {:ok, t()} | {:error, term()}
  def from_external(opportunity) when is_map(opportunity) do
    opportunity = Validation.sanitize(opportunity)

    with {:ok, id} <- Validation.required_string(opportunity, "id"),
         {:ok, spacecraft_ref} <- Validation.required_string(opportunity, "spacecraft_ref"),
         {:ok, ground_station_ref} <-
           Validation.required_string(opportunity, "ground_station_ref"),
         {:ok, pool_ref} <-
           Validation.required_string(opportunity, "antenna_or_service_pool_ref"),
         {:ok, service_ref} <-
           Validation.required_string(opportunity, "service_profile_ref"),
         {:ok, starts_at} <- Validation.datetime(opportunity, "starts_at"),
         {:ok, ends_at} <- Validation.datetime(opportunity, "ends_at"),
         {:ok, expires_at} <- Validation.datetime(opportunity, "expires_at"),
         true <- DateTime.before?(starts_at, ends_at),
         {:ok, availability} <-
           Validation.member(opportunity, "availability", @availability),
         {:ok, synthetic} <- Validation.boolean(opportunity, "synthetic"),
         {:ok, extensions} <- Validation.object(opportunity, "extensions") do
      {:ok,
       %__MODULE__{
         id: id,
         spacecraft_ref: spacecraft_ref,
         ground_station_ref: ground_station_ref,
         antenna_or_service_pool_ref: pool_ref,
         service_profile_ref: service_ref,
         starts_at: starts_at,
         ends_at: ends_at,
         expires_at: expires_at,
         availability: availability,
         estimated_capacity: opportunity["estimated_capacity"],
         synthetic: synthetic,
         extensions: extensions,
         evidence: opportunity
       }}
    else
      false -> Validation.malformed("ends_at")
      error -> error
    end
  end

  def from_external(_opportunity), do: Validation.malformed(:opportunity)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = opportunity) do
    %{
      "id" => opportunity.id,
      "spacecraft_ref" => opportunity.spacecraft_ref,
      "ground_station_ref" => opportunity.ground_station_ref,
      "antenna_or_service_pool_ref" => opportunity.antenna_or_service_pool_ref,
      "service_profile_ref" => opportunity.service_profile_ref,
      "starts_at" => DateTime.to_iso8601(opportunity.starts_at),
      "ends_at" => DateTime.to_iso8601(opportunity.ends_at),
      "expires_at" => DateTime.to_iso8601(opportunity.expires_at),
      "availability" => Atom.to_string(opportunity.availability),
      "estimated_capacity" => opportunity.estimated_capacity,
      "synthetic" => opportunity.synthetic,
      "extensions" => opportunity.extensions
    }
  end
end
