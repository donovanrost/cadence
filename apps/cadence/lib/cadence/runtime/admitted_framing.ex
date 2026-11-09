defmodule Cadence.Runtime.AdmittedFraming do
  @moduledoc """
  Overlays a source's admitted profile framing on a frame's evidence metadata before decode
  (`docs/apogee/domain/framing-ingress.md`, DECISIONS #33).

  Only sources whose admitted entry has profile framing authority carry framing. For every other
  source this is a no-op, so decode keeps using the transport's `ingress_metadata`. Admitted
  values win over transport values key by key. Atom keys take precedence in
  `TMFrameIngress.frame_codec_opts/1`.
  """

  alias Cadence.Ingress.RawEvidence

  @keys [
    {"frame_size", :frame_size},
    {"secondary_header_length", :secondary_header_length},
    {"ocf_length", :ocf_length},
    {"fecf", :fecf}
  ]

  @spec overlay(RawEvidence.t(), map() | nil) :: RawEvidence.t()
  def overlay(%RawEvidence{} = raw_evidence, nil), do: raw_evidence

  def overlay(%RawEvidence{} = raw_evidence, framing) when is_map(framing) do
    additions =
      for {key, atom} <- @keys, Map.has_key?(framing, key), into: %{}, do: {atom, framing[key]}

    %{raw_evidence | metadata: Map.merge(raw_evidence.metadata || %{}, additions)}
  end
end
