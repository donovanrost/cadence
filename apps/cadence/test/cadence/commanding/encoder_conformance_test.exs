defmodule Cadence.Commanding.EncoderConformanceTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, EncodingStep, RuntimeDefinition}
  alias Cadence.Catalog.Command.{Invocation, TypeEncoding, WireEncoding}
  alias Cadence.Commanding.Encoder

  test "fixed string and binary fields reject overlong values instead of truncating them" do
    for type <- [:string, :binary] do
      definition = definition(type, 16)
      assert {:error, _} = Encoder.encode(definition, %{"value" => "abc"})
      assert {:ok, %{binary: <<97, 0>>}} = Encoder.encode(definition, %{"value" => "a"})
      assert {:ok, %{binary: <<97, 98>>}} = Encoder.encode(definition, %{"value" => "ab"})
    end
  end

  test "string width is measured in encoded bytes without cutting UTF-8 codepoints" do
    definition = definition(:string, 16)
    assert {:ok, %{binary: <<195, 169>>}} = Encoder.encode(definition, %{"value" => "é"})
    assert {:error, _} = Encoder.encode(definition, %{"value" => "€"})
  end

  test "boolean encoding admits booleans and does not mask integer values" do
    definition = definition(:boolean, 1)
    assert {:ok, %{binary: <<128>>}} = Encoder.encode(definition, %{"value" => true})
    assert {:ok, %{binary: <<0>>}} = Encoder.encode(definition, %{"value" => false})

    for value <- [-1, 0, 1, 2, 255] do
      assert {:error, _} = Encoder.encode(definition, %{"value" => value})
    end
  end

  test "a narrower layout step cannot silently mask a wider argument" do
    definition = definition(:integer, 16)
    [step] = definition.encoding_steps
    narrower = %{definition | size_bits: 8, encoding_steps: [%{step | size_bits: 8}]}
    assert {:error, _} = Encoder.encode(narrower, %{"value" => 257})
  end

  test "unsupported signed encodings do not silently become two's complement" do
    for mode <- [:sign_magnitude, :ones_complement] do
      definition = encoding(definition(:integer, 8), %{signed: true, integer_encoding: mode})
      assert {:error, _} = Encoder.encode(definition, %{"value" => -1})
    end
  end

  test "unsupported floating-point encodings do not silently become IEEE754" do
    definition = encoding(definition(:float, 32), %{float_encoding: :mil_std_1750a})
    assert {:error, _} = Encoder.encode(definition, %{"value" => 1.0})
  end

  test "float32 overflow is rejected before emitting an infinity bit pattern" do
    definition = encoding(definition(:float, 32), %{float_encoding: :ieee754})
    assert {:ok, %{binary: <<63, 128, 0, 0>>}} = Encoder.encode(definition, %{"value" => 1.0})
    assert {:error, _} = Encoder.encode(definition, %{"value" => 1.0e100})
  end

  test "unsupported string termination and charset are not reinterpreted as raw UTF-8" do
    for attrs <- [%{string_termination: :length_prefixed}, %{charset: "UTF-16"}] do
      definition = encoding(definition(:string, 32), attrs)
      assert {:error, _} = Encoder.encode(definition, %{"value" => "a"})
    end
  end

  test "overlapping steps and out-of-layout writes return errors" do
    definition = definition(:integer, 8)
    [step] = definition.encoding_steps
    overlap = %{definition | encoding_steps: [step, step]}
    outside = %{definition | encoding_steps: [%{step | bit_offset: 8}]}
    assert {:error, _} = Encoder.encode(overlap, %{"value" => 1})
    assert {:error, _} = Encoder.encode(outside, %{"value" => 1})
  end

  test "little-endian and bit-packed layouts preserve their exact wire bits" do
    little = encoding(definition(:integer, 16), %{byte_order: :little_endian})
    assert {:ok, %{binary: <<52, 18>>}} = Encoder.encode(little, %{"value" => 0x1234})
    packed = definition(:integer, 3)
    [step] = packed.encoding_steps

    packed = %{
      packed
      | size_bits: 8,
        encoding_steps: [
          %EncodingStep{step_kind: :fixed_value, fixed_value: 3, bit_offset: 0, size_bits: 2},
          %{step | bit_offset: 2}
        ]
    }

    assert {:ok, %{binary: <<232>>}} = Encoder.encode(packed, %{"value" => 5})
  end

  test "null strings reserve a terminator and ASCII values preserve the declared character set" do
    null = encoding(definition(:string, 16), %{string_termination: :null})
    assert {:ok, %{binary: <<97, 0>>}} = Encoder.encode(null, %{"value" => "a"})
    assert {:error, _} = Encoder.encode(null, %{"value" => "ab"})
    assert {:error, _} = Encoder.encode(null, %{"value" => <<0>>})
    ascii = encoding(definition(:string, 16), %{charset: "ASCII"})
    assert {:ok, %{binary: <<65, 0>>}} = Encoder.encode(ascii, %{"value" => "A"})
    assert {:error, _} = Encoder.encode(ascii, %{"value" => "é"})
  end

  test "wide little-endian booleans preserve their declared byte order" do
    little = encoding(definition(:boolean, 16), %{byte_order: :little_endian})
    assert {:ok, %{binary: <<1, 0>>}} = Encoder.encode(little, %{"value" => true})
    assert {:ok, %{binary: <<0, 0>>}} = Encoder.encode(little, %{"value" => false})
  end

  test "enumerated numeric values retain signed bounds through resolution and encoding" do
    signed =
      encoding(definition(:enumerated, 8), %{
        encoding_type: :integer,
        signed: true,
        integer_encoding: :twos_complement
      })

    for value <- [-1, "-1"] do
      assert {:ok, resolved} = Invocation.resolve(signed, %{"value" => value})
      assert {:ok, %{binary: <<255>>}} = Encoder.encode(signed, resolved)
    end

    for value <- [-129, "-129", "not a number"] do
      assert {:error, _} = Encoder.encode(signed, %{"value" => value})
    end
  end

  test "fixed and default wire values cannot conceal overflow or unsupported formats" do
    for type <- [:string, :binary, :float], field <- [:default_value, :fixed_value] do
      definition = definition(type, if(type == :float, do: 32, else: 16))
      [spec] = definition.argument_specs
      value = if type == :float, do: 1.0e100, else: "abc"

      assert {:error, _} =
               WireEncoding.definition(%{
                 definition
                 | argument_specs: [Map.put(spec, field, value)]
               })
    end
  end

  test "layout admission rejects oversized buffers, out-of-layout writes and alternate origins before allocation" do
    definition = definition(:integer, 8)
    [step] = definition.encoding_steps

    for invalid <- [
          %{definition | size_bits: 1_000_000_000},
          %{definition | max_size_bits: 7},
          %{definition | encoding_steps: [%{step | bit_offset: 8}]},
          %{definition | encoding_steps: [%{step | bit_offset_from: :previous_entry}]},
          %{definition | encoding_steps: [%{step | bit_offset: -1}]},
          %{definition | size_bits: nil, encoding_steps: [%{step | size_bits: 1_000_000_000}]}
        ] do
      assert {:error, _} = Encoder.encode(invalid, %{"value" => 1})
    end
  end

  test "the complete padded payload including opcode fits the bounded output" do
    definition = %RuntimeDefinition{size_bits: 8 * 1_048_576}
    assert {:ok, %{size_bytes: 1_048_576}} = Encoder.encode(definition, %{})

    assert {:ok, %{size_bytes: 1}} =
             Encoder.encode(%{definition | size_bits: 8, max_size_bits: 1_000_000_000}, %{})

    assert {:error, _} = Encoder.encode(%{definition | opcode: 1, opcode_size_bits: 1}, %{})
  end

  test "ambiguous argument identities and missing references cannot select a different value" do
    definition = definition(:integer, 8)
    [spec] = definition.argument_specs
    [step] = definition.encoding_steps

    for invalid <- [
          %{definition | argument_specs: [spec, spec]},
          %{definition | argument_specs: [spec, %{spec | argument_id: "other"}]},
          %{definition | encoding_steps: [%{step | argument_id: "missing"}]},
          %{definition | argument_specs: List.duplicate(spec, 4097)},
          %{definition | encoding_steps: List.duplicate(step, 4097)}
        ] do
      assert {:error, _} = Encoder.encode(invalid, %{"value" => 1})
    end
  end

  test "unknown encoding names retain unsupported identity through document normalization" do
    for {type, bits, field} <- [
          {:integer, 8, "integer_encoding"},
          {:integer, 8, "byte_order"},
          {:integer, 8, "encoding_type"},
          {:float, 32, "float_encoding"},
          {:string, 16, "string_termination"}
        ] do
      definition = definition(type, bits)
      [spec] = definition.argument_specs

      encoding =
        TypeEncoding.new(%{
          "encoding_type" => to_string(type),
          "size_bits" => bits,
          field => "unsupported-future-format"
        })

      assert {:error, :unsupported_command_wire_definition} =
               WireEncoding.definition(%{
                 definition
                 | argument_specs: [%{spec | encoding: encoding}]
               })
    end
  end

  test "a resolved map cannot silently discard an unknown argument or override a fixed argument" do
    definition = definition(:integer, 8)
    assert {:error, _} = Encoder.encode(definition, %{"value" => 1, "unknown" => 2})
    [spec] = definition.argument_specs

    assert {:error, _} =
             Encoder.encode(%{definition | argument_specs: [%{spec | fixed_value: 3}]}, %{
               "value" => 1
             })
  end

  defp encoding(definition, attrs) do
    [spec] = definition.argument_specs
    %{definition | argument_specs: [%{spec | encoding: struct!(spec.encoding, attrs)}]}
  end

  defp definition(type, bits) do
    %RuntimeDefinition{
      size_bits: bits,
      argument_specs: [
        %ArgumentSpec{
          argument_id: "value",
          name: "value",
          base_type: type,
          required: true,
          encoding: %TypeEncoding{encoding_type: type, size_bits: bits}
        }
      ],
      encoding_steps: [
        %EncodingStep{
          step_kind: :argument_ref,
          argument_id: "value",
          bit_offset: 0,
          size_bits: bits
        }
      ]
    }
  end
end
