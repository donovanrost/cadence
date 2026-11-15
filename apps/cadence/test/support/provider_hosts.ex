defmodule Cadence.TestSupport.ProviderHosts do
  @moduledoc """
  The test environment's resolver for provider hosts (OutboundGuard): the suite's fake names
  (`*.test`) resolve to loopback, which test config allows; `*.invalid` never resolves; anything
  else goes to real DNS. The guard still checks every answer.
  """

  @spec resolve(binary()) :: {:ok, [:inet.ip_address()]} | {:error, term()}
  def resolve(host) do
    cond do
      String.ends_with?(host, ".invalid") -> {:error, :nxdomain}
      String.ends_with?(host, ".test") -> {:ok, [{127, 0, 0, 1}]}
      true -> dns(host)
    end
  end

  defp dns(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, address} -> {:ok, [address]}
      {:error, _not_literal} -> :inet.getaddrs(charlist, :inet)
    end
  end
end
