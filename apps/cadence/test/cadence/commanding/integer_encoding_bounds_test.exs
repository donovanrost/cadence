defmodule Cadence.Commanding.IntegerEncodingBoundsTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, EncodingStep, RuntimeDefinition}
  alias Cadence.Catalog.Command.{Invocation, TypeEncoding}
  alias Cadence.Commanding.Encoder

  test "an eight-bit argument cannot resolve or encode 999 as the different value 231" do
    definition = definition(8, false)

    results =
      {Invocation.resolve(definition, %{"amount" => 999}),
       Encoder.encode(definition, %{"amount" => 999})}

    assert {{:error, _}, {:error, _}} = results
  end

  test "unsigned boundaries preserve all representable bits and reject both sides outside them" do
    for bits <- [1, 7, 8, 16, 64],
        byte_order <- [:big_endian, :little_endian],
        byte_order != :little_endian or rem(bits, 8) == 0 do
      definition = definition(bits, false, byte_order)
      max_value = :erlang.bsl(1, bits) - 1
      assert {:ok, values} = Invocation.resolve(definition, %{"amount" => max_value})
      assert {:ok, encoded} = Encoder.encode(definition, values)
      assert encoded.size_bytes == div(bits + 7, 8)

      for value <- [-1, max_value + 1] do
        assert {:error, _} = Invocation.resolve(definition, %{"amount" => value})
        assert {:error, _} = Encoder.encode(definition, %{"amount" => value})
      end
    end
  end

  test "signed boundaries preserve two's-complement bytes and reject overflow and underflow" do
    for byte_order <- [:big_endian, :little_endian] do
      definition = definition(8, true, byte_order)

      for {value, bytes} <- [{-128, <<128>>}, {127, <<127>>}] do
        assert {:ok, values} = Invocation.resolve(definition, %{"amount" => value})
        assert {:ok, %{binary: ^bytes}} = Encoder.encode(definition, values)
      end

      for value <- [-129, 128] do
        assert {:error, _} = Invocation.resolve(definition, %{"amount" => value})
        assert {:error, _} = Encoder.encode(definition, %{"amount" => value})
      end
    end
  end

  test "defaults, fixed arguments, fixed layout values and opcodes cannot bypass bounds" do
    definition = definition(8, false)
    [spec] = definition.argument_specs

    for field <- [:default_value, :fixed_value] do
      invalid = %{definition | argument_specs: [Map.put(spec, field, 256)]}
      assert {:error, _} = Invocation.resolve(invalid, %{})
    end

    assert {:error, _} =
             Encoder.encode(%{definition | opcode: 256, opcode_size_bits: 8}, %{"amount" => 2})

    fixed = %{
      definition
      | argument_specs: [],
        encoding_steps: [
          %EncodingStep{step_kind: :fixed_value, fixed_value: 256, bit_offset: 0, size_bits: 8}
        ]
    }

    assert {:error, _} = Encoder.encode(fixed, %{})
  end

  defp definition(bits, signed, byte_order \\ :big_endian) do
    %RuntimeDefinition{
      size_bits: bits,
      argument_specs: [
        %ArgumentSpec{
          argument_id: "amount",
          name: "amount",
          base_type: :integer,
          required: true,
          encoding: %TypeEncoding{
            encoding_type: :integer,
            size_bits: bits,
            signed: signed,
            byte_order: byte_order
          }
        }
      ],
      encoding_steps: [
        %EncodingStep{
          step_kind: :argument_ref,
          argument_id: "amount",
          bit_offset: 0,
          size_bits: bits
        }
      ]
    }
  end
end
