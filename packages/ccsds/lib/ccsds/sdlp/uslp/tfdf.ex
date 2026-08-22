defmodule CCSDS.SDLP.USLP.TFDF do
  @moduledoc """
  Unified Space Data Link Protocol Transfer Frame Data Field header codec.

  The three-bit construction rule determines whether the optional 16-bit
  First Header Pointer or Last Valid Octet Pointer is present. Fixed-length
  packet and access data zones use a pointer; variable-length data zones do
  not.
  """

  @type construction_rule ::
          :packets_spanning_frames
          | :start_access_sdu
          | :continue_access_sdu
          | :octet_stream
          | :start_segment
          | :continue_segment
          | :last_segment
          | :unsegmented

  @rules %{
    packets_spanning_frames: 0,
    start_access_sdu: 1,
    continue_access_sdu: 2,
    octet_stream: 3,
    start_segment: 4,
    continue_segment: 5,
    last_segment: 6,
    unsegmented: 7
  }
  @reverse_rules Map.new(@rules, fn {name, value} -> {value, name} end)
  @pointer_rules [:packets_spanning_frames, :start_access_sdu, :continue_access_sdu]

  @upid_packets 0
  @upid_cop1 1
  @upid_copp 2
  @upid_sdls 3
  @upid_octet_stream 4
  @upid_mission_specific 5
  @upid_only_idle 31

  @spec upid(:packets | :cop1 | :copp | :sdls | :octet_stream | :mission_specific | :only_idle) ::
          0..31
  def upid(:packets), do: @upid_packets
  def upid(:cop1), do: @upid_cop1
  def upid(:copp), do: @upid_copp
  def upid(:sdls), do: @upid_sdls
  def upid(:octet_stream), do: @upid_octet_stream
  def upid(:mission_specific), do: @upid_mission_specific
  def upid(:only_idle), do: @upid_only_idle

  @spec pointer_rule?(construction_rule()) :: boolean()
  def pointer_rule?(rule), do: rule in @pointer_rules

  @spec encode(construction_rule(), 0..31, non_neg_integer() | nil) ::
          {:ok, binary()} | {:error, term()}
  def encode(rule, upid, pointer) do
    with {:ok, encoded_rule} <- encode_rule(rule),
         :ok <- validate_upid(upid),
         :ok <- validate_pointer(rule, pointer) do
      header = <<encoded_rule::3, upid::5>>

      if pointer_rule?(rule),
        do: {:ok, header <> <<pointer::16>>},
        else: {:ok, header}
    end
  end

  @spec decode(binary()) ::
          {:ok,
           %{
             construction_rule: construction_rule(),
             upid: 0..31,
             pointer: non_neg_integer() | nil
           }, binary()}
          | {:error, term()}
  def decode(<<encoded_rule::3, upid::5, rest::binary>>) do
    with {:ok, rule} <- decode_rule(encoded_rule) do
      decode_pointer(rule, upid, rest)
    end
  end

  def decode(_binary), do: {:error, :truncated_uslp_tfdf_header}

  @spec validate_for_frame_type(construction_rule(), :fixed | :variable) ::
          :ok | {:error, term()}
  def validate_for_frame_type(rule, :fixed)
      when rule in [:packets_spanning_frames, :start_access_sdu, :continue_access_sdu],
      do: :ok

  def validate_for_frame_type(rule, :variable)
      when rule in [:octet_stream, :start_segment, :continue_segment, :last_segment, :unsegmented],
      do: :ok

  def validate_for_frame_type(rule, frame_type),
    do: {:error, {:construction_rule_frame_type_mismatch, rule, frame_type}}

  defp encode_rule(rule) do
    case Map.fetch(@rules, rule) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_uslp_construction_rule, rule}}
    end
  end

  defp decode_rule(value) do
    case Map.fetch(@reverse_rules, value) do
      {:ok, rule} -> {:ok, rule}
      :error -> {:error, {:invalid_uslp_construction_rule, value}}
    end
  end

  defp validate_upid(value) when is_integer(value) and value in 0..31, do: :ok
  defp validate_upid(value), do: {:error, {:invalid_field, :upid, value}}

  defp validate_pointer(rule, value)
       when rule in @pointer_rules and is_integer(value) and value in 0..0xFFFF,
       do: :ok

  defp validate_pointer(rule, nil) when rule not in @pointer_rules, do: :ok

  defp validate_pointer(rule, value),
    do: {:error, {:invalid_uslp_tfdf_pointer, rule, value}}

  defp decode_pointer(rule, upid, <<pointer::16, rest::binary>>) when rule in @pointer_rules do
    {:ok, %{construction_rule: rule, upid: upid, pointer: pointer}, rest}
  end

  defp decode_pointer(rule, _upid, _rest) when rule in @pointer_rules,
    do: {:error, :truncated_uslp_tfdf_pointer}

  defp decode_pointer(rule, upid, rest) do
    {:ok, %{construction_rule: rule, upid: upid, pointer: nil}, rest}
  end
end
