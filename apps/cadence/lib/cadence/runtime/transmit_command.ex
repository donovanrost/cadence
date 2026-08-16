defmodule Cadence.Runtime.TransmitCommand do
  @moduledoc """
  Exact, receiver-owned Control-to-Data request to transmit one command.
  """

  @type t :: %__MODULE__{
          transmit_request_id: binary(),
          content_sha256: binary(),
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          transport_binding_id: binary(),
          occurred_at: DateTime.t(),
          command_queue_entry_id: binary(),
          command_request_id: binary(),
          source_endpoint_ref: binary(),
          mission_model_revision_id: binary(),
          command_id: binary(),
          command_name: binary() | nil,
          layout_kind: atom() | nil,
          preferred_uplink_service: binary() | nil,
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term(),
          encoded_binary_base64: binary(),
          encoded_size_bytes: non_neg_integer(),
          metadata: map()
        }

  @enforce_keys [
    :transmit_request_id,
    :content_sha256,
    :mission_id,
    :realized_contact_id,
    :path_id,
    :transport_binding_id,
    :occurred_at,
    :command_queue_entry_id,
    :command_request_id,
    :source_endpoint_ref,
    :mission_model_revision_id,
    :command_id,
    :encoded_binary_base64,
    :encoded_size_bytes,
    :metadata
  ]
  defstruct @enforce_keys ++
              [
                :command_name,
                :layout_kind,
                :preferred_uplink_service,
                :apid,
                :service_type,
                :service_subtype,
                :opcode
              ]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    encoded_base64 = Map.get(attrs, :encoded_binary_base64)
    encoded_size = Map.get(attrs, :encoded_size_bytes)

    with {:ok, encoded_binary} <- decode(encoded_base64),
         :ok <- exact_size(encoded_binary, encoded_size),
         :ok <- required_binaries(attrs),
         %DateTime{} = occurred_at <- Map.get(attrs, :occurred_at),
         metadata when is_map(metadata) <- Map.get(attrs, :metadata, %{}) do
      content_sha256 = Base.encode16(:crypto.hash(:sha256, encoded_binary), case: :lower)

      {:ok,
       struct!(
         __MODULE__,
         attrs
         |> Map.take(Map.keys(__MODULE__.__struct__()))
         |> Map.put(:content_sha256, content_sha256)
         |> Map.put(:occurred_at, occurred_at)
         |> Map.put(:metadata, metadata)
       )}
    else
      :error -> {:error, :invalid_transmit_command_encoding}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_transmit_command}
    end
  end

  defp decode(value) when is_binary(value), do: Base.decode64(value)
  defp decode(_value), do: :error

  defp exact_size(binary, size) when is_integer(size) and size >= 0 do
    if byte_size(binary) == size,
      do: :ok,
      else: {:error, :transmit_command_size_mismatch}
  end

  defp exact_size(_binary, _size), do: {:error, :invalid_transmit_command_size}

  defp required_binaries(attrs) do
    fields = [
      :transmit_request_id,
      :mission_id,
      :realized_contact_id,
      :path_id,
      :transport_binding_id,
      :command_queue_entry_id,
      :command_request_id,
      :source_endpoint_ref,
      :mission_model_revision_id,
      :command_id
    ]

    case Enum.find(fields, fn field ->
           value = Map.get(attrs, field)
           not (is_binary(value) and value != "")
         end) do
      nil -> :ok
      field -> {:error, {:invalid_transmit_command, field}}
    end
  end
end
