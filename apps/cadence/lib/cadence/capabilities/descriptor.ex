defmodule Cadence.Capabilities.Descriptor do
  @moduledoc """
  Declares the platform-visible contract for one registered first-party
  capability family.
  """

  @type kind :: :semantic_handler | :managed_application | :projection | :transport_extension
  @type scope :: :mission | :source_endpoint | :realized_contact | :path | :transport

  @type input_stage ::
          :raw_evidence | :transfer_frame | :space_packet | :encapsulation_packet | :app_pdu

  @type replay_mode :: :deterministic
  @type state_mode :: :stateless | :stateful

  @type t :: %__MODULE__{
          family_key: atom(),
          kind: kind(),
          supported_scopes: [scope()],
          input_stages: [input_stage()],
          partition_affinity: atom(),
          config_schema: module() | nil,
          emitted_record_kinds: [atom()],
          emitted_action_kinds: [atom()],
          replay_mode: replay_mode(),
          state_mode: state_mode()
        }

  defstruct [
    :family_key,
    :kind,
    :partition_affinity,
    :config_schema,
    supported_scopes: [],
    input_stages: [],
    emitted_record_kinds: [],
    emitted_action_kinds: [],
    replay_mode: :deterministic,
    state_mode: :stateless
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      family_key: Map.fetch!(attrs, :family_key),
      kind: Map.fetch!(attrs, :kind),
      supported_scopes: Map.get(attrs, :supported_scopes, []),
      input_stages: Map.get(attrs, :input_stages, []),
      partition_affinity: Map.fetch!(attrs, :partition_affinity),
      config_schema: Map.get(attrs, :config_schema),
      emitted_record_kinds: Map.get(attrs, :emitted_record_kinds, []),
      emitted_action_kinds: Map.get(attrs, :emitted_action_kinds, []),
      replay_mode: Map.get(attrs, :replay_mode, :deterministic),
      state_mode: Map.get(attrs, :state_mode, :stateless)
    }
  end
end
