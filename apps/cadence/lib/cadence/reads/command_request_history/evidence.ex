defmodule Cadence.Reads.CommandRequestHistory.Evidence do
  @moduledoc """
  The record that matched each verifier, loaded in one query per record kind for a page:

    * `telemetry_sample` → `{kind: "telemetry", sample_id, point_id, point_name, packet_id,
      evidence_id, quality, raw_value_json, engineering_value_json, unit, received_at,
      generated_at}` (`unit` from the catalog, `nil` when none);
    * `transport_action_request` → `{kind: "transport", source: "action_request", record_id,
      action (its action_kind), signal_phase, at (requested_at), recorded_at: nil}`, only when it
      belongs to this request and the verifier's attempt;
    * `transport_capability_record` → `{kind: "transport", source: "capability_record",
      record_id, action (its event_kind), signal_phase (as the verifier matched it), at and
      recorded_at (recorded_at)}`.

  `evidence_status`: `ready` (the record), `pending` (nothing matched yet and the verifier is
  still pending), `unmatched` (it ended with nothing matched, e.g. timed out), `unavailable` (a
  match is recorded but its record can't be read here).

  Schemaless reads by table (as `CommandHistory`), so the read plane takes no other context's
  row schemas.
  """

  import Ecto.Query

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.PointInfo
  alias Cadence.Repo

  @spec load(binary(), binary(), binary(), [map()]) :: map()
  def load(org, mission, request_id, verifiers) do
    ids = Enum.group_by(verifiers, & &1.matched_record_kind, & &1.matched_record_id)

    %{
      "telemetry_sample" =>
        org |> samples(mission, ids["telemetry_sample"]) |> with_units(org, mission),
      "transport_action_request" =>
        actions(org, mission, request_id, ids["transport_action_request"]),
      "transport_capability_record" =>
        capability_records(org, mission, ids["transport_capability_record"])
    }
  end

  @spec for_verifier(map(), map()) :: {binary(), map() | nil}
  def for_verifier(_evidence, %{matched_record_id: nil, lifecycle_state: "pending"}),
    do: {"pending", nil}

  def for_verifier(_evidence, %{matched_record_id: nil}), do: {"unmatched", nil}

  def for_verifier(evidence, %{matched_record_kind: kind, matched_record_id: id} = verifier) do
    case evidence |> Map.get(kind, %{}) |> Map.get(id) do
      nil ->
        {"unavailable", nil}

      {attempt_id, record} when attempt_id == verifier.command_release_attempt_id ->
        {"ready", record}

      {_other_attempt, _record} ->
        {"unavailable", nil}

      record ->
        {"ready", record}
    end
  end

  defp samples(_org, _mission, nil), do: %{}

  defp samples(org, mission, ids) do
    from(s in "telemetry_samples",
      where: s.organization_id == ^org and s.mission_id == ^mission and s.sample_id in ^ids,
      select: %{
        sample_id: s.sample_id,
        point_id: s.point_id,
        point_name: s.point_name,
        packet_id: s.packet_id,
        evidence_id: s.evidence_id,
        quality_state: s.quality_state,
        raw_value: s.raw_value,
        engineering_value: s.engineering_value,
        receipt_time: type(s.receipt_time, :utc_datetime_usec),
        generation_time: type(s.generation_time, :utc_datetime_usec)
      }
    )
    |> Repo.all()
    |> Map.new(fn s ->
      {s.sample_id,
       %{
         kind: "telemetry",
         sample_id: s.sample_id,
         point_id: s.point_id,
         point_name: s.point_name,
         packet_id: s.packet_id,
         evidence_id: s.evidence_id,
         quality: s.quality_state,
         raw_value_json: value_json(s.raw_value),
         engineering_value_json: value_json(s.engineering_value),
         received_at: s.receipt_time,
         generated_at: s.generation_time
       }}
    end)
  end

  # U70: the point's catalog unit ("= 8.0 °C (raw 412)"), `nil` when the catalog has none.
  defp with_units(samples, _org, _mission) when map_size(samples) == 0, do: samples

  defp with_units(samples, org, mission) do
    points = PointInfo.by_id(org, mission)

    Map.new(samples, fn {id, sample} ->
      unit = points |> Map.get(sample.point_id, PointInfo.unknown()) |> Map.get(:unit)
      {id, Map.put(sample, :unit, unit)}
    end)
  end

  # Keyed with the attempt it belongs to, so a verifier only takes its own attempt's action.
  defp actions(_org, _mission, _request_id, nil), do: %{}

  defp actions(org, mission, request_id, ids) do
    from(a in "transport_action_requests",
      where:
        a.organization_id == ^org and a.mission_id == ^mission and
          a.command_request_id == ^request_id and a.action_request_id in ^ids,
      select: %{
        action_request_id: a.action_request_id,
        command_release_attempt_id: a.command_release_attempt_id,
        action_kind: a.action_kind,
        signal_phase: a.signal_phase,
        requested_at: type(a.requested_at, :utc_datetime_usec)
      }
    )
    |> Repo.all()
    |> Map.new(fn a ->
      {a.action_request_id,
       {a.command_release_attempt_id,
        %{
          kind: "transport",
          source: "action_request",
          record_id: a.action_request_id,
          action: a.action_kind,
          signal_phase: a.signal_phase,
          at: a.requested_at,
          recorded_at: nil
        }}}
    end)
  end

  defp capability_records(_org, _mission, nil), do: %{}

  defp capability_records(org, mission, ids) do
    from(c in "transport_capability_records",
      where:
        c.organization_id == ^org and c.mission_id == ^mission and c.transport_record_id in ^ids,
      select: %{
        transport_record_id: c.transport_record_id,
        event_kind: c.event_kind,
        family_key: c.family_key,
        metadata: c.metadata,
        recorded_at: type(c.recorded_at, :utc_datetime_usec)
      }
    )
    |> Repo.all()
    |> Map.new(fn c ->
      {c.transport_record_id,
       %{
         kind: "transport",
         source: "capability_record",
         record_id: c.transport_record_id,
         action: c.event_kind,
         signal_phase: capability_phase(c),
         at: c.recorded_at,
         recorded_at: c.recorded_at
       }}
    end)
  end

  # The phase the verifier matched it at (VerifierTransportSignals.signal_phase/2): the record's
  # own signal_phase / verifier_phase, else acceptance for the uplink gateway's handled input.
  defp capability_phase(record) do
    metadata = JsonDocument.unwrap_value(record.metadata || %{})
    metadata = if is_map(metadata), do: metadata, else: %{}

    case metadata["signal_phase"] || metadata["verifier_phase"] do
      phase when is_binary(phase) and phase != "" -> phase
      _none -> default_phase(record.family_key, record.event_kind)
    end
  end

  defp default_phase("uplink_gateway", "control_input_handled"), do: "acceptance"
  defp default_phase(_family, _kind), do: nil

  defp value_json(nil), do: nil
  defp value_json(document), do: document |> JsonDocument.unwrap_value() |> Jason.encode!()
end
