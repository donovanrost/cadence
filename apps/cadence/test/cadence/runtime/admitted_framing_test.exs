defmodule Cadence.Runtime.AdmittedFramingTest do
  use ExUnit.Case, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.TMFrameIngress
  alias Cadence.Runtime.{AdmittedFraming, SourceRuntimeBases}

  defp evidence(metadata), do: struct(RawEvidence, metadata: metadata, raw: <<>>)

  test "without admitted framing the transport's ingress metadata decides" do
    raw = evidence(%{"frame_size" => 1115, "ocf_length" => 0})
    assert AdmittedFraming.overlay(raw, nil) == raw
    assert {:ok, opts} = TMFrameIngress.frame_codec_opts(raw)
    assert opts[:frame_size] == 1115
  end

  test "admitted profile framing wins key by key over transport metadata" do
    raw = evidence(%{"frame_size" => 1115, "ocf_length" => 0, "fecf" => false})
    overlaid = AdmittedFraming.overlay(raw, %{"frame_size" => 1279, "fecf" => true})

    assert {:ok, opts} = TMFrameIngress.frame_codec_opts(overlaid)
    assert opts[:frame_size] == 1279
    assert opts[:fecf] == true
    assert opts[:ocf_length] == 0
  end

  test "source bases keep framing, so sources with different framing get different models" do
    model = %{
      mission_model_revision_id: "m1",
      mission_model_content_sha256: "s",
      runtime_plans: %{}
    }

    assert {:ok, index} =
             SourceRuntimeBases.new(%{
               "src-a" => Map.put(model, :framing, %{"frame_size" => 1279}),
               "src-b" => model
             })

    assert {:ok, %{framing: %{"frame_size" => 1279}}} = SourceRuntimeBases.fetch(index, "src-a")
    assert {:ok, basis_b} = SourceRuntimeBases.fetch(index, "src-b")
    refute Map.has_key?(basis_b, :framing)
  end
end
