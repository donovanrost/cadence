defmodule Cadence.Telemetry.Resolve do
  @moduledoc """
  Resolve stage: attach mission identity and schema to a parsed unit.
  """

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Telemetry.{PacketEnvelope, ParsedUnit, ResolvedUnit, SpacePacket, UnknownUnit}

  @spec resolve(PacketEnvelope.t(), ParsedUnit.t(), ConfigBundle.t() | nil) :: ResolvedUnit.t()
  def resolve(%PacketEnvelope{} = envelope, parsed_unit, bundle) do
    {identity, identity_trace} = resolve_identity(envelope, bundle)
    {schema, schema_trace} = resolve_schema(parsed_unit, identity, bundle)

    format = format_from_parsed(parsed_unit)
    config_version_used = config_version_used(bundle, envelope)

    decision_trace =
      %{
        evidence_used: identity_trace.evidence_used ++ schema_trace.evidence_used,
        rules_applied: identity_trace.rules_applied ++ schema_trace.rules_applied
      }
      |> maybe_add_version_mismatch(envelope, bundle)

    %ResolvedUnit{
      packet_id: envelope.packet_id,
      mission_id: envelope.mission_id,
      envelope: envelope,
      parsed_unit: parsed_unit,
      format: format,
      identity: identity,
      schema: schema,
      decision_trace: decision_trace,
      config_version_used: config_version_used
    }
  end

  defp resolve_identity(%PacketEnvelope{} = envelope, %ConfigBundle{} = bundle) do
    scid = evidence_value(envelope, :scid)
    target_hint = evidence_value(envelope, :target_hint)

    cond do
      is_integer(scid) ->
        case scid_target_map(bundle) |> Map.get(scid) do
          nil ->
            {{:unresolved, :no_scid_mapping, %{scid: scid}},
             %{evidence_used: [:scid], rules_applied: [:scid_target_map]}}

          target_id ->
            {{:ok, target_id}, %{evidence_used: [:scid], rules_applied: [:scid_target_map]}}
        end

      not is_nil(target_hint) ->
        case resolve_target_hint(bundle, target_hint) do
          {:ok, target_id} ->
            {{:ok, target_id},
             %{evidence_used: [:target_hint], rules_applied: [:target_hint_lookup]}}

          {:error, reason} ->
            {{:unresolved, reason, target_hint},
             %{evidence_used: [:target_hint], rules_applied: [:target_hint_lookup]}}
        end

      true ->
        {{:unresolved, :no_identity_evidence, nil}, %{evidence_used: [], rules_applied: []}}
    end
  end

  defp resolve_identity(%PacketEnvelope{} = _envelope, _bundle) do
    {{:unresolved, :missing_config_bundle, nil}, %{evidence_used: [], rules_applied: []}}
  end

  defp resolve_schema(parsed_unit, identity, %ConfigBundle{} = bundle) do
    format = format_from_parsed(parsed_unit)

    case {format, identity, parsed_unit} do
      {:space_packet, {:ok, target_id}, {:space_packet, %SpacePacket{} = packet}} ->
        resolve_space_packet_schema(packet, target_id, bundle)

      {:space_packet, {:ok, _target_id}, _} ->
        {{:schema_unavailable, :missing_space_packet},
         %{evidence_used: [:target], rules_applied: [:space_packet_schema]}}

      {:space_packet, {:unresolved, _reason, _hint}, _} ->
        {{:schema_unavailable, :missing_identity},
         %{evidence_used: [], rules_applied: [:space_packet_schema]}}

      {:space_packet, {:ambiguous, _candidates, _hint}, _} ->
        {{:schema_unavailable, :ambiguous_identity},
         %{evidence_used: [], rules_applied: [:space_packet_schema]}}

      {:encap_packet, _identity, _} ->
        {{:unsupported_format, :encap_packet},
         %{evidence_used: [], rules_applied: [:unsupported_format]}}

      {:unknown, _identity, {:unknown, %UnknownUnit{reason: reason}}} ->
        {{:unsupported_format, reason},
         %{evidence_used: [], rules_applied: [:unsupported_format]}}

      _ ->
        {{:schema_unavailable, :no_match},
         %{evidence_used: [], rules_applied: [:schema_unavailable]}}
    end
  end

  defp resolve_schema(_parsed_unit, _identity, _bundle) do
    {{:schema_unavailable, :missing_config_bundle},
     %{evidence_used: [], rules_applied: [:schema_unavailable]}}
  end

  defp resolve_space_packet_schema(%SpacePacket{} = packet, target_id, %ConfigBundle{} = bundle) do
    target = fetch_target(bundle, target_id)
    definition_set_id = target && Map.get(target, :definition_set_id)
    apid = SpacePacket.get_apid(packet)

    cond do
      is_nil(definition_set_id) ->
        {{:uncataloged_target, target_id},
         %{evidence_used: [:target], rules_applied: [:definition_set_lookup]}}

      not is_integer(apid) ->
        {{:unknown_apid, target_id, definition_set_id, apid},
         %{evidence_used: [:target, :apid], rules_applied: [:packet_catalog_by_apid]}}

      true ->
        case fetch_packet_def(bundle, definition_set_id, apid) do
          nil ->
            {{:unknown_apid, target_id, definition_set_id, apid},
             %{evidence_used: [:target, :apid], rules_applied: [:packet_catalog_by_apid]}}

          packet_def ->
            {{:ok, packet_def},
             %{evidence_used: [:target, :apid], rules_applied: [:packet_catalog_by_apid]}}
        end
    end
  end

  defp fetch_packet_def(%ConfigBundle{} = bundle, definition_set_id, apid) do
    case Map.get(bundle.packet_catalog, :by_apid) do
      by_apid when is_map(by_apid) -> Map.get(by_apid, {definition_set_id, apid})
      _ -> nil
    end
  end

  defp fetch_target(%ConfigBundle{} = bundle, target_id) do
    case bundle.targets_by_identifier do
      %{} = targets_by_identifier ->
        Map.get(targets_by_identifier, target_id)

      _ ->
        Enum.find(bundle.targets, fn target -> Map.get(target, :id) == target_id end)
    end
  end

  defp scid_target_map(%ConfigBundle{} = bundle) do
    Enum.reduce(bundle.targets, %{}, fn target, acc ->
      case Map.get(target, :scid) do
        scid when is_integer(scid) -> Map.put(acc, scid, Map.get(target, :id))
        _ -> acc
      end
    end)
  end

  defp resolve_target_hint(%ConfigBundle{} = bundle, hint) do
    case Ecto.UUID.cast(hint) do
      {:ok, uuid} ->
        if fetch_target(bundle, uuid), do: {:ok, uuid}, else: {:error, :unknown_target_hint}

      _ ->
        resolve_target_hint_from_lookup(bundle, hint)
    end
  end

  defp resolve_target_hint_from_lookup(%ConfigBundle{} = bundle, hint) do
    lookup = bundle.target_ids_by_identifier || %{}

    case Map.get(lookup, hint) do
      nil -> {:error, :unknown_target_hint}
      target_id -> {:ok, target_id}
    end
  end

  defp evidence_value(%PacketEnvelope{} = envelope, kind) do
    envelope.evidence
    |> Enum.find(&(&1.kind == kind))
    |> case do
      nil -> nil
      evidence -> evidence.value
    end
  end

  defp format_from_parsed({:space_packet, _}), do: :space_packet
  defp format_from_parsed({:encap_packet, _}), do: :encap_packet
  defp format_from_parsed({:unknown, _}), do: :unknown

  defp config_version_used(%ConfigBundle{config_version: version}, _envelope)
       when is_integer(version),
       do: version

  defp config_version_used(_bundle, %PacketEnvelope{config_version_seen: version}) do
    version
  end

  defp maybe_add_version_mismatch(
         trace,
         %PacketEnvelope{config_version_seen: seen},
         %ConfigBundle{config_version: used}
       )
       when is_integer(seen) and is_integer(used) and seen != used do
    Map.put(trace, :config_version_mismatch, %{seen: seen, used: used})
  end

  defp maybe_add_version_mismatch(trace, _envelope, _bundle), do: trace
end
