defmodule Cadence.Runtime.IngressEvidence do
  @moduledoc """
  Validates the exact ingress evidence accepted by the data plane.

  Source-endpoint resolution belongs to the control handoff. Evidence that
  names a source endpoint must therefore already carry its spacecraft identity
  before it enters runtime execution.
  """

  alias Cadence.Ingress.RawEvidence

  @spec validate(RawEvidence.t()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def validate(%RawEvidence{
        source_endpoint_ref: source_endpoint_ref,
        spacecraft_id: spacecraft_id
      })
      when is_binary(source_endpoint_ref) and source_endpoint_ref != "" and
             (not is_binary(spacecraft_id) or spacecraft_id == "") do
    {:error, {:unresolved_ingress_source_endpoint, source_endpoint_ref}}
  end

  def validate(%RawEvidence{} = raw_evidence), do: {:ok, raw_evidence}
end
