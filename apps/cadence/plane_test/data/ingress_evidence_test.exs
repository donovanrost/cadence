defmodule Cadence.Runtime.IngressEvidenceTest do
  use ExUnit.Case, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.IngressEvidence

  test "accepts source-endpoint evidence only after the control handoff resolves it" do
    unresolved =
      RawEvidence.new(%{
        mission_id: "mission-data-plane",
        source_endpoint_ref: "endpoint-alpha",
        raw: <<1, 2, 3>>
      })

    assert {:error, {:unresolved_ingress_source_endpoint, "endpoint-alpha"}} =
             IngressEvidence.validate(unresolved)

    resolved = %{unresolved | spacecraft_id: "spacecraft-alpha"}
    assert {:ok, ^resolved} = IngressEvidence.validate(resolved)
  end

  test "accepts evidence without a managed source endpoint" do
    evidence = RawEvidence.new(%{mission_id: "mission-data-plane", raw: <<1, 2, 3>>})

    assert {:ok, ^evidence} = IngressEvidence.validate(evidence)
  end
end
