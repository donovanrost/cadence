defmodule Cadence.Runtime.ProcessedIngressBatch do
  @moduledoc """
  Ordered batch of processed ingress results awaiting async persistence.
  """

  @type t :: %__MODULE__{
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          provider_binding_id: binary(),
          processing_results: [Cadence.processing_result()]
        }

  defstruct [
    :mission_id,
    :realized_contact_id,
    :path_id,
    :provider_binding_id,
    processing_results: []
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      mission_id: Map.fetch!(attrs, :mission_id),
      realized_contact_id: Map.fetch!(attrs, :realized_contact_id),
      path_id: Map.fetch!(attrs, :path_id),
      provider_binding_id: Map.fetch!(attrs, :provider_binding_id),
      processing_results: Map.get(attrs, :processing_results, [])
    }
  end

  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{processing_results: processing_results})
      when is_list(processing_results) do
    length(processing_results)
  end
end
