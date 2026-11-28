defmodule Cadence.TestSupport.BindingFleet do
  @moduledoc """
  A populated binding set for tests (#447): `craft` spacecraft, each with a source endpoint and one
  telemetry instance and rule per handled APID, plus one mission-scoped instance. Craft 1 handles
  one APID fewer (the last), so there is more than one distinct configuration.
  """

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.PacketDefinition

  @apids [42, 43, 44]

  @doc "The source endpoint id of craft `n`."
  def endpoint(n), do: "spacecraft_runtime:sc-#{n}"

  @doc "The spacecraft and source endpoint rows craft `1..n` (or the range given) need, in the mission."
  def persist_endpoints!(org, mission, craft) do
    for n <- if(is_integer(craft), do: 1..craft, else: craft) do
      {:ok, _} =
        Cadence.SpacecraftStore.persist_spacecraft(
          org,
          Cadence.Spacecraft.new(%{
            spacecraft_id: "sc-#{n}",
            organization_id: org,
            mission_id: mission,
            display_name: "SC-#{n}"
          })
        )

      {:ok, _} =
        Cadence.SourceEndpointFixtures.persist(
          org,
          SourceEndpoint.new(%{
            source_endpoint_id: endpoint(n),
            organization_id: org,
            mission_id: mission,
            spacecraft_id: "sc-#{n}",
            source_ref: "provider/sc-#{n}"
          })
        )
    end

    :ok
  end

  @doc """
  The set. Options: `:packet_id` (a function of the craft number, to put an endpoint where it must
  not be), `:packet_version` (`%{apid => version}`), `:organization?` (false leaves the set
  unscoped, so storage infers the organization from the mission).
  """
  def build(org, mission, binding_set_id, version, craft, opts \\ []) do
    packet_id = Keyword.get(opts, :packet_id, fn _n -> nil end)
    versions = Keyword.get(opts, :packet_version, %{})
    revision = "mission_model_revision:storage"

    instances =
      for n <- 1..craft, apid <- apids(n) do
        CapabilityInstance.new(%{
          capability_instance_id: "mission_model_telemetry:#{revision}:#{endpoint(n)}:hk-#{apid}",
          family_key: :definition_bound_telemetry,
          target_scope: :source_endpoint,
          source_endpoint_ref: endpoint(n),
          runtime_configuration:
            packet(org, mission, apid, packet_id.(n), Map.get(versions, apid, 1))
        })
      end

    mission_instance =
      CapabilityInstance.new(%{
        capability_instance_id: "mission_model_telemetry:#{revision}:mission:hk-99",
        family_key: :definition_bound_telemetry,
        target_scope: :mission,
        runtime_configuration: packet(org, mission, 99, nil, 1)
      })

    rules =
      Enum.map(instances, fn instance ->
        BindingRule.new(%{
          binding_rule_id: instance.capability_instance_id <> ":rule",
          capability_instance_id: instance.capability_instance_id,
          selector: %{
            scope: %{
              target_scope: :source_endpoint,
              source_endpoint_ref: instance.source_endpoint_ref
            },
            match: %{packet_kind: :space_packet, apid: instance.runtime_configuration.apid}
          },
          priority: 100,
          fanout_mode: :exclusive
        })
      end)

    BindingSet.new(%{
      organization_id: if(Keyword.get(opts, :organization?, true), do: org),
      mission_id: mission,
      binding_set_id: binding_set_id,
      version: version,
      capability_instances: instances ++ [mission_instance],
      rules: rules
    })
  end

  defp apids(1), do: Enum.drop(@apids, -1)
  defp apids(_n), do: @apids

  defp packet(org, mission, apid, id, version) do
    PacketDefinition.new(%{
      organization_id: org,
      mission_id: mission,
      packet_definition_id: id || "hk-#{apid}",
      packet_name: "HK#{apid}",
      apid: apid,
      version: version,
      fields: [
        %{
          field_id: "counter",
          name: "counter",
          offset_bits: 0,
          size_bits: if(version == 1, do: 16, else: 32),
          data_type: :uint
        }
      ]
    })
  end
end
