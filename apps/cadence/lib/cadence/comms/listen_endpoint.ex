defmodule Cadence.Comms.ListenEndpoint do
  @moduledoc "Pure TCP bind and shared admission rules used at save time and at runtime."

  @wildcard_hosts ["0.0.0.0", "::", "", "*"]
  # The shared reader needs the two SCID header bytes. The upper bound matches the
  # spacecraft profile's TM frame-size ceiling.
  @shared_frame_sizes 2..2048

  @type t :: %{host: binary(), port: pos_integer()}

  @spec bind(binary() | nil, non_neg_integer()) :: t() | nil
  def bind(host, port) when is_integer(port) and port in 1..65_535,
    do: %{host: bind_host(host || "127.0.0.1"), port: port}

  def bind(_host, _port), do: nil

  # InboundSocket binds an unspecified address when the host isn't a literal IP.
  defp bind_host(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> ip |> :inet.ntoa() |> List.to_string()
      {:error, _reason} -> "0.0.0.0"
    end
  end

  defp bind_host(_host), do: "0.0.0.0"

  @spec overlaps?(t(), t()) :: boolean()
  def overlaps?(%{port: port, host: a}, %{port: port, host: b}),
    do: a == b or a in @wildcard_hosts or b in @wildcard_hosts

  def overlaps?(_claim, _endpoint), do: false

  @spec shared_frame_size?(term()) :: boolean()
  def shared_frame_size?(size), do: is_integer(size) and size in @shared_frame_sizes
end
