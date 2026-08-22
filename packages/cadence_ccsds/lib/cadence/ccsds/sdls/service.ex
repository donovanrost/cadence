defmodule Cadence.CCSDS.SDLS.Service do
  @moduledoc """
  CCSDS 355.0-B-2 protection eligibility for data-link services.
  """

  @protected %{
    tm: [:virtual_channel_packet, :virtual_channel_access],
    tc: [:map_packet, :map_access, :virtual_channel_packet, :virtual_channel_access],
    aos: [:virtual_channel_packet, :bitstream, :virtual_channel_access],
    uslp: [:map_packet, :map_access, :map_octet_stream]
  }

  alias Cadence.CCSDS.SDLS.Channel

  @spec validate(Channel.t(), atom(), atom()) :: :ok | {:error, term()}
  def validate(%Channel{} = channel, service, service_type) do
    with :ok <- validate(channel.protocol, service, service_type) do
      validate_map_context(channel, service)
    end
  end

  @spec validate(atom(), atom(), atom()) :: :ok | {:error, term()}
  def validate(:tm, :virtual_channel_secondary_header, :authentication), do: :ok

  def validate(protocol, service, service_type) do
    if service in Map.get(@protected, protocol, []) and
         service_type in [:authentication, :encryption, :authenticated_encryption] do
      :ok
    else
      {:error, {:sdls_service_not_protected, protocol, service, service_type}}
    end
  end

  defp validate_map_context(%Channel{protocol: protocol, map_id: nil}, service)
       when service in [:map_packet, :map_access, :map_octet_stream],
       do: {:error, {:sdls_map_id_required, protocol, service}}

  defp validate_map_context(_channel, _service), do: :ok
end
