defmodule Cadence.GroundNetworks.DeliveryProfile do
  @moduledoc "Validated provider-owned delivery profile."

  alias Cadence.GroundNetworks.Validation

  @directions %{"downlink" => :downlink, "uplink" => :uplink, "bidirectional" => :bidirectional}
  @states %{"ready" => :ready, "degraded" => :degraded, "unavailable" => :unavailable}

  @type t :: %__MODULE__{
          id: binary(),
          version: pos_integer(),
          display_name: binary(),
          direction: atom(),
          delivery_kind: binary(),
          supported_service_profile_refs: [binary()],
          state: atom(),
          operator_summary: binary(),
          diagnostics: map(),
          extensions: map(),
          evidence: map()
        }

  defstruct [
    :id,
    :version,
    :display_name,
    :direction,
    :delivery_kind,
    :state,
    :operator_summary,
    supported_service_profile_refs: [],
    diagnostics: %{},
    extensions: %{},
    evidence: %{}
  ]

  @spec from_external(map()) :: {:ok, t()} | {:error, term()}
  def from_external(profile) when is_map(profile) do
    profile = Validation.sanitize(profile)

    with {:ok, id} <- Validation.required_string(profile, "id"),
         {:ok, version} <- Validation.positive_integer(profile, "version"),
         {:ok, display_name} <- Validation.required_string(profile, "display_name"),
         {:ok, direction} <- Validation.member(profile, "direction", @directions),
         {:ok, delivery_kind} <- Validation.required_string(profile, "delivery_kind"),
         {:ok, service_refs} <-
           Validation.string_list(profile, "supported_service_profile_refs"),
         {:ok, state} <- Validation.member(profile, "state", @states),
         {:ok, operator_summary} <- Validation.required_string(profile, "operator_summary"),
         {:ok, diagnostics} <- Validation.object(profile, "diagnostics"),
         {:ok, extensions} <- Validation.object(profile, "extensions") do
      {:ok,
       %__MODULE__{
         id: id,
         version: version,
         display_name: display_name,
         direction: direction,
         delivery_kind: delivery_kind,
         supported_service_profile_refs: service_refs,
         state: state,
         operator_summary: operator_summary,
         diagnostics: diagnostics,
         extensions: extensions,
         evidence: profile
       }}
    end
  end

  def from_external(_profile), do: Validation.malformed(:delivery_profile)
end
