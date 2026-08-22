defmodule Cadence.ActionRequests.ProviderRequest do
  @moduledoc """
  Typed provider-adapter delivery request emitted by transport-local protocol
  logic and executed by a path-local provider runtime.
  """

  @type t :: %__MODULE__{
          provider_binding_id: binary(),
          provider_adapter_key: atom(),
          command_release_attempt_id: binary() | nil,
          command_queue_entry_id: binary() | nil,
          command_request_id: binary() | nil,
          source_endpoint_ref: binary() | nil,
          mission_model_revision_id: binary() | nil,
          command_id: binary() | nil,
          command_name: binary() | nil,
          transport_profile: atom() | nil,
          payloads_base64: [binary()],
          payload_count: non_neg_integer(),
          payload_size_bytes: non_neg_integer() | nil,
          metadata: map()
        }

  defstruct [
    :provider_binding_id,
    :provider_adapter_key,
    :command_release_attempt_id,
    :command_queue_entry_id,
    :command_request_id,
    :source_endpoint_ref,
    :mission_model_revision_id,
    :command_id,
    :command_name,
    :transport_profile,
    :payloads_base64,
    :payload_count,
    :payload_size_bytes,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_binding_id: Map.fetch!(attrs, :provider_binding_id),
      provider_adapter_key: Map.fetch!(attrs, :provider_adapter_key),
      command_release_attempt_id: Map.get(attrs, :command_release_attempt_id),
      command_queue_entry_id: Map.get(attrs, :command_queue_entry_id),
      command_request_id: Map.get(attrs, :command_request_id),
      source_endpoint_ref: Map.get(attrs, :source_endpoint_ref),
      mission_model_revision_id: Map.get(attrs, :mission_model_revision_id),
      command_id: Map.get(attrs, :command_id),
      command_name: Map.get(attrs, :command_name),
      transport_profile: Map.get(attrs, :transport_profile),
      payloads_base64: Map.get(attrs, :payloads_base64, []),
      payload_count: Map.get(attrs, :payload_count, 0),
      payload_size_bytes: Map.get(attrs, :payload_size_bytes),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
