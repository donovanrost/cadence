defmodule Cadence.Simulator.UplinkRuntime do
  @moduledoc false

  alias Cadence.CCSDS.Core.SDUOctets

  @spec build(keyword() | nil, term()) :: %{
          ctx_base: map() | nil,
          encode_opts: keyword() | nil,
          sdu_base: SDUOctets.t() | nil
        }
  def build(nil, _metrics_scope) do
    %{ctx_base: nil, encode_opts: nil, sdu_base: nil}
  end

  def build(opts, metrics_scope) do
    scid = opts[:uplink_scid] || opts[:scid]
    vcid = opts[:uplink_vcid] || opts[:vcid]
    map_id = opts[:uplink_map_id]

    ctx_base =
      %{
        frame_size: opts[:frame_size],
        scid: scid,
        vcid: vcid,
        map_id: map_id
      }
      |> maybe_put_metrics_scope(metrics_scope)

    sdu_base = %SDUOctets{
      profile: opts[:profile],
      scid: scid,
      vcid: vcid,
      map_id: map_id,
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: <<>>,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    encode_opts =
      opts
      |> Keyword.take([:frame_size, :secondary_header_length, :ocf_length])
      |> maybe_put_metrics_opt(metrics_scope)

    %{
      ctx_base: ctx_base,
      encode_opts: encode_opts,
      sdu_base: sdu_base
    }
  end

  defp maybe_put_metrics_scope(ctx, nil), do: ctx

  defp maybe_put_metrics_scope(ctx, metrics_scope),
    do: Map.put(ctx, :metrics_scope, metrics_scope)

  defp maybe_put_metrics_opt(opts, nil), do: opts

  defp maybe_put_metrics_opt(opts, metrics_scope),
    do: Keyword.put(opts, :metrics_scope, metrics_scope)
end
