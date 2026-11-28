defmodule Cadence.GroundNetworks.EphemerisReasons do
  @moduledoc """
  The closed reason codes of ephemeris outcomes (#972) and the fixed sentence each reads as.

  An outcome stores only a code, never a provider's own text: a failure's detail can carry
  provider evidence, so it goes to the sanitized warning log at most. Reads word a code with
  `detail/2`, a fixed sentence per code.

    * `failed`: `provider_<category>` for each `ProviderError` category, the
      `provider_version_not_found` the run raises itself, and `other` for anything else.
    * `not_ready`: the `ProviderScheduling` refusal codes on a routing rule, the spacecraft-wide
      `spacecraft_not_found`, and `no_ready_route` when no refusal names this provider's rule.
  """

  alias Cadence.GroundNetworks.ProviderError

  @failed %{
    "provider_invalid_request" => "The provider refused the orbit as invalid.",
    "provider_authentication_failed" => "The provider didn't accept Cadence's credentials.",
    "provider_authorization_failed" =>
      "The provider doesn't allow this account to upload orbits.",
    "provider_unsupported_capability" => "The provider doesn't support orbit uploads.",
    "provider_not_found" => "The provider doesn't know this spacecraft.",
    "provider_conflict" => "The provider refused the orbit because of a conflict.",
    "provider_no_capacity" => "The provider has no capacity to take the orbit right now.",
    "provider_not_ready" => "The provider isn't ready to take orbits yet.",
    "provider_rate_limited" => "The provider is limiting requests; Cadence will retry.",
    "provider_unavailable" => "The provider couldn't be reached.",
    "provider_timeout" => "The provider didn't answer in time.",
    "provider_ambiguous_outcome" => "The provider's answer didn't say whether it took the orbit.",
    "provider_malformed_response" => "The provider's answer couldn't be read.",
    "provider_error" => "The provider returned an error.",
    "provider_version_not_found" => "The provider version this route uses is gone.",
    "other" => "The upload failed."
  }

  @categories %{
    invalid_request: "provider_invalid_request",
    authentication_failed: "provider_authentication_failed",
    authorization_failed: "provider_authorization_failed",
    unsupported_capability: "provider_unsupported_capability",
    not_found: "provider_not_found",
    conflict: "provider_conflict",
    no_capacity: "provider_no_capacity",
    provider_not_ready: "provider_not_ready",
    rate_limited: "provider_rate_limited",
    provider_unavailable: "provider_unavailable",
    known_timeout: "provider_timeout",
    ambiguous_outcome: "provider_ambiguous_outcome",
    malformed_response: "provider_malformed_response",
    provider_error: "provider_error"
  }

  @not_ready %{
    "mission_provider_not_validated" => "The provider version hasn't validated.",
    "mission_provider_not_active" => "The provider version isn't active.",
    "mission_provider_archived" => "The provider is archived.",
    "mission_provider_not_found" => "The provider version this route pins is gone.",
    "mission_provider_profiles_not_synced" => "The provider's profiles haven't synced.",
    "provider_service_profile_not_active" => "The route's service profile isn't active.",
    "provider_delivery_profile_not_ready" => "The route's delivery profile isn't ready.",
    "provider_profile_version_not_available" => "The route's profile version isn't available.",
    "provider_profile_direction_not_supported" => "The route's profiles don't support downlink.",
    "provider_profiles_not_compatible" =>
      "The route's service and delivery profiles don't match.",
    "provider_route_not_ready" => "The provider route isn't ready.",
    "invalid_provider_profile_reference" => "The route names a profile that doesn't exist.",
    "transport_not_found" => "The route's transport is gone.",
    "transport_not_active" => "The route's transport version isn't active.",
    "transport_provider_snapshot_mismatch" =>
      "The route's transport no longer matches the provider.",
    "transport_runtime_profile_mismatch" =>
      "The route's transport profile doesn't match its runtime.",
    "transport_runtime_profile_not_materialized" => "The route's transport isn't set up yet.",
    "direct_transport_not_provider_schedulable" =>
      "The route uses a direct transport, which the provider can't schedule.",
    "missing_downlink_path" => "The route has no downlink path set up.",
    "contact_link_assignment_not_found" => "The route has no link assignment.",
    "contact_path_template_not_found" => "The route's path template is gone.",
    "source_endpoint_not_found" => "The route's source endpoint is gone.",
    "missing_provider_spacecraft_reference" => "The spacecraft has no provider-side ID.",
    "spacecraft_not_found" => "The spacecraft is gone.",
    "no_ready_route" => "No route to the provider is ready."
  }

  @doc "The `failed` reason codes, in the order the docs list them."
  @spec failed_codes() :: [binary()]
  def failed_codes, do: Map.keys(@failed) |> Enum.sort()

  @doc "The `not_ready` reason codes."
  @spec not_ready_codes() :: [binary()]
  def not_ready_codes, do: Map.keys(@not_ready) |> Enum.sort()

  @doc "The closed code of an upload failure: never the provider's own text."
  @spec failed_code(term()) :: binary()
  def failed_code(%ProviderError{category: category}),
    do: Map.get(@categories, category, "provider_error")

  def failed_code(:provider_version_not_found), do: "provider_version_not_found"
  def failed_code(_reason), do: "other"

  @doc "A refusal code closed to the `not_ready` vocabulary (`no_ready_route` if unknown)."
  @spec not_ready_code(term()) :: binary()
  def not_ready_code(code) do
    code = to_string(code)
    if Map.has_key?(@not_ready, code), do: code, else: "no_ready_route"
  end

  @doc "The fixed sentence a cause's code reads as, or nil (no code, or `norad_id_missing`)."
  @spec detail(binary(), binary() | nil) :: binary() | nil
  def detail("failed", code), do: Map.get(@failed, code || "other", @failed["other"])
  def detail("not_ready", code), do: Map.get(@not_ready, code || "no_ready_route")
  def detail(_cause, _code), do: nil
end
