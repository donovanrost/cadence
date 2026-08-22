defmodule Cadence.Control.Ingress do
  @moduledoc """
  Control-plane handoff from mutable source configuration to exact data-plane
  ingress evidence.
  """

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.Ingress, as: RuntimeIngress
  alias Cadence.SourceEndpoints

  @spec process_and_persist(RawEvidence.t()) ::
          {:ok, RuntimeIngress.processing_result()} | {:error, term()}
  def process_and_persist(%RawEvidence{} = raw_evidence) do
    with {:ok, %RawEvidence{} = resolved_raw_evidence} <-
           SourceEndpoints.resolve_raw_evidence(raw_evidence) do
      RuntimeIngress.process_and_persist(resolved_raw_evidence)
    end
  end
end
