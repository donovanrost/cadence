defmodule CCSDS.CFDP do
  @moduledoc """
  CCSDS 727.0-B-5 File Delivery Protocol primitives.

  The namespace contains dependency-free PDU and standard user-operation
  codecs, checksum procedures, and pure Class 1 and Class 2 transaction state.
  Filestore access, persistence, scheduling, clocks, authorization, user-
  operation execution, and transport binding remain caller concerns.
  """

  @type transmission_mode :: :acknowledged | :unacknowledged
  @type direction :: :toward_file_receiver | :toward_file_sender
  @type condition ::
          :no_error
          | :positive_ack_limit_reached
          | :keep_alive_limit_reached
          | :invalid_transmission_mode
          | :filestore_rejection
          | :file_checksum_failure
          | :file_size_error
          | :nak_limit_reached
          | :inactivity_detected
          | :invalid_file_structure
          | :check_limit_reached
          | :unsupported_checksum_type
          | :suspend_request_received
          | :cancel_request_received

  @conditions %{
    no_error: 0x0,
    positive_ack_limit_reached: 0x1,
    keep_alive_limit_reached: 0x2,
    invalid_transmission_mode: 0x3,
    filestore_rejection: 0x4,
    file_checksum_failure: 0x5,
    file_size_error: 0x6,
    nak_limit_reached: 0x7,
    inactivity_detected: 0x8,
    invalid_file_structure: 0x9,
    check_limit_reached: 0xA,
    unsupported_checksum_type: 0xB,
    suspend_request_received: 0xE,
    cancel_request_received: 0xF
  }
  @conditions_by_code Map.new(@conditions, fn {name, code} -> {code, name} end)

  @spec condition_code(condition()) :: 0..15
  def condition_code(condition), do: Map.fetch!(@conditions, condition)

  @spec condition(0..15) :: {:ok, condition()} | {:error, term()}
  def condition(code) when is_integer(code) do
    case Map.fetch(@conditions_by_code, code) do
      {:ok, condition} -> {:ok, condition}
      :error -> {:error, {:reserved_condition_code, code}}
    end
  end
end
