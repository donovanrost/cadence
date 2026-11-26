defmodule Cadence.Catalog.TelemetryBinding do
  @moduledoc """
  The ids telemetry decom gives a mission model revision's packet bindings. One owner for the
  format: `Cadence.Applications.TelemetryDecom` builds its capability instances and binding rules
  with it, and telemetry storage rebuilds a stored observation's `binding_rule_id` with it instead
  of storing it (DECISIONS #103), so the two can't drift apart.

      mission_model_telemetry:<revision>:<source endpoint>:<packet definition>        capability instance
      mission_model_telemetry:<revision>:<source endpoint>:<packet definition>:rule   binding rule

  A spacecraft's managed source endpoint ID is defined by `Cadence.Ids`. A decom
  configuration may name another endpoint; its rule ids follow the same format with that endpoint,
  so `binding_rule_id/3` (by spacecraft) doesn't produce them.

  Changing the format changes how existing rows read back: stored observations carry only the
  parts, so a change here needs a migration of the derived rows first.
  """

  alias Cadence.Ids

  @doc "The capability instance id for one packet definition on one source endpoint."
  @spec capability_instance_id(binary(), binary(), binary()) :: binary()
  def capability_instance_id(revision_id, source_endpoint_id, packet_definition_id)
      when is_binary(revision_id) and is_binary(source_endpoint_id) and
             is_binary(packet_definition_id),
      do: "mission_model_telemetry:#{revision_id}:#{source_endpoint_id}:#{packet_definition_id}"

  @doc "The binding rule id for a capability instance id."
  @spec rule_id(binary()) :: binary()
  def rule_id(capability_instance_id) when is_binary(capability_instance_id),
    do: capability_instance_id <> ":rule"

  @doc """
  The binding rule id a packet observation of `spacecraft_id` carries, decoded by `producer_id`
  (its packet definition) under mission model revision `revision_id`, on the spacecraft's managed
  source endpoint.
  """
  @spec binding_rule_id(binary(), binary(), binary()) :: binary()
  def binding_rule_id(revision_id, spacecraft_id, producer_id)
      when is_binary(spacecraft_id) do
    revision_id
    |> capability_instance_id(Ids.managed_source_endpoint_id(spacecraft_id), producer_id)
    |> rule_id()
  end
end
