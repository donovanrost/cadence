defmodule Cadence.Protocol.Origin do
  @moduledoc """
  Where a packet came from (#1078 P5 slice E1a): an origin descriptor built at decode from facts
  ingest already has, with no lookup. It is provenance, never identity: it enters no packet,
  sample, observation or `parameter_update` id, so existing ids and replays are unchanged.

      %{v: 1, kind: :direct, source_endpoint_id, scid, vcid, map_id, apid, relay: nil}

  `source_endpoint_id` is the endpoint the evidence arrived on (`source_endpoint_ref`, else its
  `source_ref`, as the observation's own context names it). `kind` is `:direct` until a relay
  endpoint routes a frame to its origin craft (E1b, which fills `relay`).

  Where it is kept: on the archived packet, as `PacketRecord.provenance.origin`, only `stored/1` of
  it (`v`, `kind`, `relay`: the rest is the packet's own fields, rebuilt by `rebuild/3`), and, in
  memory, whole on the sample (`Cadence.Telemetry.Sample.origin`, runtime only) so a later slice can
  key per-origin state on it. It is **not** written to the observation store: that row gains
  nothing in E1a, and a sample's origin is read back from its archived packet
  (`Cadence.Reads.SampleOrigin`).
  """

  alias Cadence.Ingress.RawEvidence

  @version 1

  @type t :: %{
          v: pos_integer(),
          kind: :direct | :relayed,
          source_endpoint_id: binary() | nil,
          scid: non_neg_integer() | nil,
          vcid: non_neg_integer() | nil,
          map_id: non_neg_integer() | nil,
          apid: non_neg_integer(),
          relay: nil | %{via_source_endpoint_id: binary(), via_scid: non_neg_integer()}
        }

  @doc """
  The origin of a packet a relay endpoint carried for another craft (E1b): `kind: :relayed`, with
  `relay` naming the endpoint it arrived on and that endpoint's own SCID. The endpoint, frame facts
  and APID are those of the evidence it arrived in, as for `direct/3`.
  """
  @spec relayed(RawEvidence.t(), map(), non_neg_integer(), non_neg_integer() | nil) :: t()
  def relayed(%RawEvidence{} = raw_evidence, tm, apid, via_scid) do
    endpoint = raw_evidence.source_endpoint_ref || raw_evidence.source_ref

    %{
      direct(raw_evidence, tm, apid)
      | kind: :relayed,
        relay: %{via_source_endpoint_id: endpoint, via_scid: via_scid}
    }
  end

  @doc "The descriptor's version."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc """
  The origin of a packet decoded from `raw_evidence`, with `tm` the frame facts (`scid`, `vcid`,
  `map_id`; an empty map for a packet that came through no transfer frame) and the packet's `apid`.
  O(1): nothing here reads anything but its arguments.
  """
  @spec direct(RawEvidence.t(), map(), non_neg_integer()) :: t()
  def direct(%RawEvidence{} = raw_evidence, tm, apid) when is_map(tm) and is_integer(apid) do
    %{
      v: @version,
      kind: :direct,
      source_endpoint_id: raw_evidence.source_endpoint_ref || raw_evidence.source_ref,
      scid: Map.get(tm, :scid),
      vcid: Map.get(tm, :vcid),
      map_id: Map.get(tm, :map_id),
      apid: apid,
      relay: nil
    }
  end

  @doc """
  What the archive keeps of an origin: only what the packet's own fields can't give back (`v`,
  `kind` and `relay`). The endpoint, SCID, VCID, MAP id and APID duplicate the archived packet's
  `source_endpoint_ref`, `tm` provenance and `apid`, so storing them again would cost bytes in the
  protocol archive for nothing (measured on the filesystem backend: +0.1 B per packet against
  +2 to +7 B per packet compressed, +134 B uncompressed, for the full descriptor).
  """
  @spec stored(t()) :: map()
  def stored(%{} = origin), do: %{v: origin.v, kind: origin.kind, relay: origin.relay}

  @doc "The full origin of an archived packet (`rebuild/3` over its record)."
  @spec from_packet(struct()) :: t() | nil
  def from_packet(%{provenance: provenance, source_endpoint_ref: ref, apid: apid}),
    do: rebuild(provenance, ref, apid)

  @doc """
  The full origin rebuilt from a packet's stored one and its own fields: the endpoint it arrived on
  (`source_endpoint_ref`, else the provenance's `source_ref`, as `direct/3` named it), the frame's
  SCID, VCID and MAP id (provenance `tm`) and the packet's `apid`. Reads the JSON form an archive
  hands back (string keys, `kind` a string) as well as decode's. `nil` when the packet has no
  stored origin (it was archived before E1a).
  """
  @spec rebuild(term(), binary() | nil, non_neg_integer() | nil) :: map() | nil
  def rebuild(%{} = provenance, source_endpoint_ref, apid) do
    case fetch(provenance, :origin) do
      %{} = stored ->
        tm = fetch(provenance, :tm) || %{}

        %{
          v: fetch(stored, :v),
          kind: fetch(stored, :kind),
          source_endpoint_id: source_endpoint_ref || fetch(provenance, :source_ref),
          scid: fetch(tm, :scid),
          vcid: fetch(tm, :vcid),
          map_id: fetch(tm, :map_id),
          apid: apid,
          relay: fetch(stored, :relay)
        }

      _none ->
        nil
    end
  end

  def rebuild(_provenance, _source_endpoint_ref, _apid), do: nil

  defp fetch(%{} = map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp fetch(_other, _key), do: nil

  @doc "An origin as plain JSON values (string keys, atoms as strings)."
  @spec to_json(map()) :: map()
  def to_json(%{} = origin) do
    Map.new(origin, fn {key, value} -> {to_string(key), json_value(value)} end)
  end

  defp json_value(%{} = map), do: to_json(map)

  defp json_value(value) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp json_value(value), do: value
end
