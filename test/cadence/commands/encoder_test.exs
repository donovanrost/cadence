defmodule Cadence.Commands.EncoderTest do
  use Cadence.DataCase, async: true

  alias Cadence.Commands.Encoder
  alias Cadence.Commands.{CommandDefinition, CommandParameter}

  describe "encode/2" do
    test "encodes a simple command with no parameters" do
      command = %CommandDefinition{
        opcode: 0x01,
        command_parameters: []
      }

      assert {:ok, binary} = Encoder.encode(command, %{})
      assert binary == <<0x00, 0x01>>
    end

    test "encodes command with single uint parameter" do
      command =
        build_command(0x10, [
          build_param("mode", "uint", bit_offset: 0, bit_length: 8)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"mode" => 1})
      # Opcode (2 bytes) + mode (1 byte)
      assert binary == <<0x00, 0x10, 0x01>>
    end

    test "encodes command with multiple parameters" do
      command =
        build_command(0x20, [
          build_param("mode", "uint", bit_offset: 0, bit_length: 8),
          build_param("value", "uint", bit_offset: 8, bit_length: 16)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"mode" => 2, "value" => 1000})
      # Opcode (2 bytes) + mode (1 byte) + value (2 bytes big-endian)
      assert binary == <<0x00, 0x20, 0x02, 0x03, 0xE8>>
    end

    test "encodes signed integer parameter" do
      command =
        build_command(0x30, [
          build_param("offset", "int", bit_offset: 0, bit_length: 16)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"offset" => -100})
      # -100 as 16-bit signed = 0xFF9C
      assert binary == <<0x00, 0x30, 0xFF, 0x9C>>
    end

    test "encodes float parameter (32-bit)" do
      command =
        build_command(0x40, [
          build_param("temp", "float", bit_offset: 0, bit_length: 32)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"temp" => 25.5})
      # 25.5 as IEEE 754 32-bit float big-endian
      <<expected::binary>> = <<25.5::big-float-32>>
      assert binary == <<0x00, 0x40>> <> expected
    end

    test "encodes boolean parameter as true" do
      command =
        build_command(0x50, [
          build_param("enabled", "boolean", bit_offset: 0, bit_length: 8)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"enabled" => true})
      assert binary == <<0x00, 0x50, 0x01>>
    end

    test "encodes boolean parameter as false" do
      command =
        build_command(0x50, [
          build_param("enabled", "boolean", bit_offset: 0, bit_length: 8)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"enabled" => false})
      assert binary == <<0x00, 0x50, 0x00>>
    end

    test "encodes string parameter with padding" do
      command =
        build_command(0x60, [
          build_param("name", "string", bit_offset: 0, bit_length: 40)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"name" => "ABC"})
      # "ABC" padded to 5 bytes
      assert binary == <<0x00, 0x60, "ABC", 0x00, 0x00>>
    end

    test "encodes enum parameter by index" do
      command =
        build_command(0x70, [
          build_param("state", "enum",
            bit_offset: 0,
            bit_length: 8,
            valid_values: ["OFF", "ON", "AUTO"]
          )
        ])

      assert {:ok, binary} = Encoder.encode(command, %{"state" => "ON"})
      # "ON" is index 1
      assert binary == <<0x00, 0x70, 0x01>>
    end

    test "uses default value when parameter not provided" do
      command =
        build_command(0x80, [
          build_param("mode", "uint",
            bit_offset: 0,
            bit_length: 8,
            required: false,
            default_value: "5"
          )
        ])

      assert {:ok, binary} = Encoder.encode(command, %{})
      assert binary == <<0x00, 0x80, 0x05>>
    end

    test "accepts atom keys in params" do
      command =
        build_command(0x10, [
          build_param("mode", "uint", bit_offset: 0, bit_length: 8)
        ])

      assert {:ok, binary} = Encoder.encode(command, %{mode: 1})
      assert binary == <<0x00, 0x10, 0x01>>
    end

    test "returns error for missing required parameter" do
      command =
        build_command(0x10, [
          build_param("mode", "uint", bit_offset: 0, bit_length: 8, required: true)
        ])

      assert {:error, {:validation, errors}} = Encoder.encode(command, %{})
      assert {"mode", "is required"} in errors
    end
  end

  describe "encode_parameter/2" do
    test "encodes uint values" do
      param = build_param("test", "uint", bit_length: 16)
      assert {:ok, <<0x01, 0x00>>} = Encoder.encode_parameter(param, 256)
    end

    test "returns error for negative uint" do
      param = build_param("test", "uint", bit_length: 16)
      assert {:error, :negative_value_for_uint} = Encoder.encode_parameter(param, -1)
    end

    test "encodes int values" do
      param = build_param("test", "int", bit_length: 16)
      assert {:ok, <<0xFF, 0xFF>>} = Encoder.encode_parameter(param, -1)
    end
  end

  describe "payload_size/1" do
    test "returns 0 for empty parameters" do
      assert Encoder.payload_size([]) == 0
    end

    test "calculates size from max offset + length" do
      params = [
        build_param("a", "uint", bit_offset: 0, bit_length: 8),
        build_param("b", "uint", bit_offset: 8, bit_length: 16)
      ]

      # (8 + 16) / 8 = 3 bytes
      assert Encoder.payload_size(params) == 3
    end

    test "handles non-byte-aligned lengths" do
      params = [
        build_param("a", "uint", bit_offset: 0, bit_length: 12)
      ]

      # 12 bits = 2 bytes (rounded up)
      assert Encoder.payload_size(params) == 2
    end
  end

  describe "insert_bits/4" do
    test "inserts byte-aligned value" do
      buffer = <<0x00, 0x00, 0x00, 0x00>>
      value = <<0xAB>>

      result = Encoder.insert_bits(buffer, 8, 8, value)
      assert result == <<0x00, 0xAB, 0x00, 0x00>>
    end

    test "inserts at beginning" do
      buffer = <<0x00, 0x00>>
      value = <<0xFF>>

      result = Encoder.insert_bits(buffer, 0, 8, value)
      assert result == <<0xFF, 0x00>>
    end

    test "inserts multi-byte value" do
      buffer = <<0x00, 0x00, 0x00, 0x00>>
      value = <<0x12, 0x34>>

      result = Encoder.insert_bits(buffer, 8, 16, value)
      assert result == <<0x00, 0x12, 0x34, 0x00>>
    end
  end

  describe "encode_parameter/2 edge cases" do
    test "raises ArgumentError for invalid data type" do
      param = %CommandParameter{
        name: "invalid_param",
        data_type: "invalid_type",
        bit_offset: 0,
        bit_length: 8,
        required: true
      }

      assert_raise ArgumentError, ~r/Invalid data type/, fn ->
        Encoder.encode_parameter(param, 42)
      end
    end

    test "accepts valid data type strings" do
      for data_type <- ["uint", "int", "float", "string", "boolean", "enum"] do
        param = %CommandParameter{
          name: "test_param",
          data_type: data_type,
          bit_offset: 0,
          bit_length: 32,
          required: true
        }

        # Should not raise - specific encodings tested elsewhere
        case data_type do
          "float" ->
            assert {:ok, _} = Encoder.encode_parameter(param, 1.0)

          "string" ->
            assert {:ok, _} = Encoder.encode_parameter(param, "test")

          "boolean" ->
            assert {:ok, _} = Encoder.encode_parameter(param, true)

          _ ->
            assert {:ok, _} = Encoder.encode_parameter(param, 1)
        end
      end
    end
  end

  # Helper functions

  defp build_command(opcode, parameters) do
    %CommandDefinition{
      opcode: opcode,
      command_parameters: parameters
    }
  end

  defp build_param(name, data_type, opts \\ []) do
    %CommandParameter{
      name: name,
      data_type: data_type,
      bit_offset: Keyword.get(opts, :bit_offset, 0),
      bit_length: Keyword.get(opts, :bit_length, 8),
      required: Keyword.get(opts, :required, true),
      default_value: Keyword.get(opts, :default_value),
      valid_values: Keyword.get(opts, :valid_values, [])
    }
  end
end
