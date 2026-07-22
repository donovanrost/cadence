defmodule Cadence.CCSDS.Conformance.CFDPSpacepacketsVerifier do
  alias Cadence.CCSDS.CFDP.Codec

  @expected_version "0.32.0"

  def run(lines) do
    result =
      Enum.reduce(lines, %{metadata: nil, cadence: 0, spacepackets: 0, binaries: []}, fn line,
                                                                                         state ->
        line
        |> String.trim()
        |> String.split("\t")
        |> verify_line(state)
      end)

    assert!(result.metadata != nil, "missing spacepackets metadata")
    assert!(result.cadence == 128, "unexpected Cadence case count")
    assert!(result.spacepackets == 11, "unexpected spacepackets case count")

    digest =
      result.binaries
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    IO.puts("External CFDP PDU interoperability PASS")
    IO.puts("implementation=spacepackets")
    IO.puts("version=#{result.metadata.version}")
    IO.puts("runtime=Python #{result.metadata.python}")
    IO.puts("cadence_generated_cases=#{result.cadence}")
    IO.puts("spacepackets_generated_cases=#{result.spacepackets}")
    IO.puts("wire_bytes_sha256=#{digest}")
  end

  defp verify_line(["META", "spacepackets", version, python], state) do
    assert!(version == @expected_version, "unexpected spacepackets version #{version}")
    %{state | metadata: %{version: version, python: python}}
  end

  defp verify_line(["RESULT", origin, _id, wire_hex], state)
       when origin in ["CADENCE", "SPACEPACKETS"] do
    wire = hex!(wire_hex)
    pdu = expect_ok(Codec.decode(wire), "Cadence rejected #{origin} CFDP PDU")
    encoded = expect_ok(Codec.encode(pdu), "Cadence could not re-encode #{origin} CFDP PDU")
    assert!(encoded == wire, "Cadence changed #{origin} CFDP PDU")

    key = if(origin == "CADENCE", do: :cadence, else: :spacepackets)
    state |> Map.update!(key, &(&1 + 1)) |> Map.update!(:binaries, &[wire | &1])
  end

  defp verify_line(fields, _state), do: raise("unexpected spacepackets result #{inspect(fields)}")

  defp expect_ok({:ok, value}, _message), do: value
  defp expect_ok(value, message), do: raise("#{message}: #{inspect(value)}")

  defp hex!(value) do
    case Base.decode16(value, case: :mixed) do
      {:ok, binary} -> binary
      :error -> raise("invalid external hexadecimal #{inspect(value)}")
    end
  end

  defp assert!(true, _message), do: :ok
  defp assert!(false, message), do: raise(message)
end

Cadence.CCSDS.Conformance.CFDPSpacepacketsVerifier.run(IO.stream(:stdio, :line))
