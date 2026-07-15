defmodule Cadence.GroundNetworks.ServiceProfile do
  @moduledoc "Validated provider-owned service profile."

  alias Cadence.GroundNetworks.Validation

  @directions %{"downlink" => :downlink, "uplink" => :uplink, "bidirectional" => :bidirectional}
  @states %{"active" => :active, "inactive" => :inactive}

  @type t :: %__MODULE__{
          id: binary(),
          version: pos_integer(),
          display_name: binary(),
          service_kind: binary(),
          direction: atom(),
          supported_delivery_kinds: [binary()],
          data_families: [binary()],
          minimum_duration_seconds: pos_integer(),
          state: atom(),
          extensions: map(),
          evidence: map()
        }

  defstruct [
    :id,
    :version,
    :display_name,
    :service_kind,
    :direction,
    :minimum_duration_seconds,
    :state,
    supported_delivery_kinds: [],
    data_families: [],
    extensions: %{},
    evidence: %{}
  ]

  @spec from_external(map()) :: {:ok, t()} | {:error, term()}
  def from_external(profile) when is_map(profile) do
    profile = Validation.sanitize(profile)

    with {:ok, id} <- Validation.required_string(profile, "id"),
         {:ok, version} <- Validation.positive_integer(profile, "version"),
         {:ok, display_name} <- Validation.required_string(profile, "display_name"),
         {:ok, service_kind} <- Validation.required_string(profile, "service_kind"),
         {:ok, direction} <- Validation.member(profile, "direction", @directions),
         {:ok, delivery_kinds} <-
           Validation.string_list(profile, "supported_delivery_kinds"),
         {:ok, data_families} <- Validation.string_list(profile, "data_families"),
         {:ok, minimum_duration} <-
           Validation.positive_integer(profile, "minimum_duration_seconds"),
         {:ok, state} <- Validation.member(profile, "state", @states),
         {:ok, extensions} <- Validation.object(profile, "extensions") do
      {:ok,
       %__MODULE__{
         id: id,
         version: version,
         display_name: display_name,
         service_kind: service_kind,
         direction: direction,
         supported_delivery_kinds: delivery_kinds,
         data_families: data_families,
         minimum_duration_seconds: minimum_duration,
         state: state,
         extensions: extensions,
         evidence: profile
       }}
    end
  end

  def from_external(_profile), do: Validation.malformed(:service_profile)
end
