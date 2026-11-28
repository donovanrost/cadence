defmodule Cadence.Protocol.Origin do
  @moduledoc """
  Where a packet came from (#1078 P5 slice E1a): an origin descriptor built at decode from facts
  ingest already has, with no lookup. It is provenance, never identity: it enters no packet,
  sample, observation or `parameter_update` id, so existing ids and replays are unchanged.

      %{v: 1, kind: :direct, source_endpoint_id, scid, vcid, map_id, apid, relay: nil}

  `source_endpoint_id` is the endpoint the evidence arrived on (`source_endpoint_ref`, else its
  `source_ref`, as the observation's own context names it). `kind` is `:direct` until a relay
  endpoint routes a frame to its origin craft (E1b, which fills `relay`).

  Where it is kept: on the archived packet (`PacketRecord.provenance.origin`) and, in memory, on the
  sample (`Cadence.Telemetry.Sample.origin`, runtime only) so a later slice can key per-origin state
  on it. It is **not** written to the observation store: that row gains nothing in E1a, and a
  sample's origin is read back from its archived packet (`Cadence.Reads.SampleOrigin`).
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
  The origin held in a packet's provenance, in the JSON form an archive hands back (string keys,
  `kind` a string) or as decode built it; `nil` when the packet has none (it was archived before
  E1a).
  """
  @spec from_provenance(term()) :: map() | nil
  def from_provenance(%{} = provenance) do
    case Map.get(provenance, :origin) || Map.get(provenance, "origin") do
      %{} = origin -> origin
      _none -> nil
    end
  end

  def from_provenance(_provenance), do: nil

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
