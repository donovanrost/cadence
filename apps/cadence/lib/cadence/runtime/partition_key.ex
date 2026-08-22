defmodule Cadence.Runtime.PartitionKey do
  @moduledoc """
  Runtime execution partition selector.

  Runtime partitions are keyed by the resolved semantic source endpoint.
  """

  alias Cadence.Ingress.RawEvidence

  @unresolved_source_endpoint_key "__unresolved_source_endpoint__"

  @type affinity :: :source_endpoint | :mission | :path | :transport

  @type t :: %__MODULE__{
          affinity: affinity(),
          value: binary()
        }

  defstruct [:affinity, :value]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      affinity: Map.fetch!(attrs, :affinity),
      value: Map.fetch!(attrs, :value)
    }
  end

  @spec from_raw_evidence(RawEvidence.t()) :: t()
  def from_raw_evidence(%RawEvidence{} = raw_evidence) do
    %__MODULE__{
      affinity: :source_endpoint,
      value: raw_evidence.source_endpoint_ref || @unresolved_source_endpoint_key
    }
  end

  @spec identifier(t()) :: binary()
  def identifier(%__MODULE__{affinity: affinity, value: value}) do
    Atom.to_string(affinity) <> ":" <> value
  end

  @spec registry_key(t()) :: {affinity(), binary()}
  def registry_key(%__MODULE__{affinity: affinity, value: value}), do: {affinity, value}
end
