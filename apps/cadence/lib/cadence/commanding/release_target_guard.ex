defmodule Cadence.Commanding.ReleaseTargetGuard do
  @moduledoc """
  SAFETY (qa #38, DECISIONS #66): a command is released only over its target spacecraft's own
  contact, uplink path and gateway. The target is the spacecraft of the request's source
  endpoint. Each piece must belong to it:

  - the realized contact: every source endpoint it serves is the target's, and it serves some;
  - the uplink path: its own source endpoint is the target's, or (when it has none) the
    routing rule it was materialized from targets that spacecraft; a path that names neither
    is refused;
  - the gateway binding: it carries a SCID (an integer, or a string that is exactly one), and
    it is the target's SCID. A binding without one is refused (`uplink_gateway_scid_unknown`),
    as is a target spacecraft without one (`release_target_scid_unknown`).

  Anything that can't be resolved is refused (fail closed).
  """

  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.Contacts.{Path, RealizedContact, TransportBinding}
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @type reason ::
          {:release_target_spacecraft_unknown, binary()}
          | {:release_contact_not_target_spacecraft, binary()}
          | {:release_path_not_target_spacecraft, binary()}
          | {:release_gateway_not_target_spacecraft, binary()}
          | {:uplink_gateway_scid_unknown, binary()}
          | {:release_target_scid_unknown, binary()}

  @doc "The spacecraft a source endpoint belongs to."
  @spec target(binary(), binary(), binary()) :: {:ok, binary()} | {:error, reason()}
  def target(org, mission, source_endpoint_ref) do
    case SourceEndpoints.fetch_source_endpoint(org, mission, source_endpoint_ref) do
      {:ok, %{spacecraft_id: id}} when is_binary(id) -> {:ok, id}
      _unknown -> {:error, {:release_target_spacecraft_unknown, source_endpoint_ref}}
    end
  end

  @doc "Whether the contact serves only the target spacecraft (and serves it)."
  @spec contact(binary(), binary(), binary(), RealizedContact.t()) :: :ok | {:error, reason()}
  def contact(org, mission, target, %RealizedContact{} = contact) do
    owners = Enum.map(contact.source_endpoint_refs, &endpoint_owner(org, mission, &1))

    if owners != [] and Enum.all?(owners, &(&1 == target)),
      do: :ok,
      else: {:error, {:release_contact_not_target_spacecraft, contact.realized_contact_id}}
  end

  @doc "Every check, for one release target."
  @spec check(binary(), binary(), binary(), RealizedContact.t(), Path.t(), TransportBinding.t()) ::
          :ok | {:error, reason()}
  def check(org, mission, source_endpoint_ref, contact, path, binding) do
    with {:ok, target} <- target(org, mission, source_endpoint_ref),
         :ok <- contact(org, mission, target, contact),
         :ok <- path(org, mission, target, path) do
      gateway(org, mission, target, binding)
    end
  end

  defp path(org, mission, target, %Path{source_endpoint_ref: ref} = path) when is_binary(ref) do
    if endpoint_owner(org, mission, ref) == target,
      do: :ok,
      else: {:error, {:release_path_not_target_spacecraft, path.path_id}}
  end

  defp path(org, mission, target, %Path{} = path) do
    with rule_id when is_binary(rule_id) <-
           (path.metadata || %{})["materialized_from_routing_rule_id"],
         {:ok, %{spacecraft_id: ^target}} <-
           RoutingRuleStore.fetch_routing_rule(org, mission, rule_id) do
      :ok
    else
      _not_the_target -> {:error, {:release_path_not_target_spacecraft, path.path_id}}
    end
  end

  defp gateway(org, mission, target, %TransportBinding{} = binding) do
    with {:ok, scid} <- binding_scid(binding.configuration),
         {:ok, %{scid: target_scid}} when is_integer(target_scid) <-
           SpacecraftStore.fetch_spacecraft(org, mission, target) do
      if scid == target_scid,
        do: :ok,
        else: {:error, {:release_gateway_not_target_spacecraft, binding.transport_binding_id}}
    else
      :unknown -> {:error, {:uplink_gateway_scid_unknown, binding.transport_binding_id}}
      _no_target_scid -> {:error, {:release_target_scid_unknown, target}}
    end
  end

  # The binding's SCID, exactly: an integer, or a string that is one whole integer.
  defp binding_scid(%{"scid" => scid}), do: parse_scid(scid)
  defp binding_scid(%{scid: scid}), do: parse_scid(scid)
  defp binding_scid(_configuration), do: :unknown

  defp parse_scid(scid) when is_integer(scid), do: {:ok, scid}

  defp parse_scid(scid) when is_binary(scid) do
    case Integer.parse(scid) do
      {parsed, ""} -> {:ok, parsed}
      _unparseable -> :unknown
    end
  end

  defp parse_scid(_other), do: :unknown

  defp endpoint_owner(org, mission, ref) do
    case SourceEndpoints.fetch_source_endpoint(org, mission, ref) do
      {:ok, %{spacecraft_id: id}} -> id
      _unknown -> nil
    end
  end
end
