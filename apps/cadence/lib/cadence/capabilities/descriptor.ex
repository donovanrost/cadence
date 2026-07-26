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
          version: pos_integer(),
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
    :version,
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
      version: Map.fetch!(attrs, :version),
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

  @kinds [:semantic_handler, :managed_application, :projection, :transport_extension]
  @scopes [:mission, :source_endpoint, :realized_contact, :path, :transport]
  @input_stages [:raw_evidence, :transfer_frame, :space_packet, :encapsulation_packet, :app_pdu]

  @spec validate(t()) :: :ok | {:error, :invalid_capability_descriptor}
  def validate(%__MODULE__{} = descriptor) do
    if valid_identity?(descriptor) and valid_execution_contract?(descriptor) and
         valid_output_contract?(descriptor) do
      :ok
    else
      {:error, :invalid_capability_descriptor}
    end
  end

  def validate(_descriptor), do: {:error, :invalid_capability_descriptor}

  defp valid_identity?(%__MODULE__{} = descriptor) do
    is_atom(descriptor.family_key) and not is_nil(descriptor.family_key) and
      is_integer(descriptor.version) and descriptor.version > 0 and descriptor.kind in @kinds
  end

  defp valid_execution_contract?(%__MODULE__{} = descriptor) do
    valid_atoms?(descriptor.supported_scopes, @scopes) and
      valid_atoms?(descriptor.input_stages, @input_stages) and
      is_atom(descriptor.partition_affinity) and not is_nil(descriptor.partition_affinity) and
      descriptor.replay_mode == :deterministic and
      descriptor.state_mode in [:stateless, :stateful]
  end

  defp valid_output_contract?(%__MODULE__{} = descriptor) do
    valid_module?(descriptor.config_schema) and valid_atoms?(descriptor.emitted_record_kinds) and
      valid_atoms?(descriptor.emitted_action_kinds)
  end

  defp valid_atoms?(values, allowed \\ nil)

  defp valid_atoms?(values, allowed) when is_list(values) do
    Enum.all?(values, fn value ->
      is_atom(value) and not is_nil(value) and (is_nil(allowed) or value in allowed)
    end) and length(Enum.uniq(values)) == length(values)
  end

  defp valid_atoms?(_values, _allowed), do: false

  defp valid_module?(nil), do: true
  defp valid_module?(module) when is_atom(module), do: module not in [true, false]
  defp valid_module?(_module), do: false
end
