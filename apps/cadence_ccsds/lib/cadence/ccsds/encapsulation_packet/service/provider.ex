defmodule Cadence.CCSDS.EncapsulationPacket.Service.Provider do
  @moduledoc """
  Pure Encapsulation Packet service provider.

  The provider maps request and indication primitives to the wire codec while
  leaving SDLP channel selection, persistence, scheduling, and transport to
  its caller.
  """

  alias Cadence.CCSDS.EncapsulationPacket
  alias Cadence.CCSDS.EncapsulationPacket.{Codec, Configuration}
  alias Cadence.CCSDS.EncapsulationPacket.Service.{Indication, Request}

  @type t :: %__MODULE__{configuration: Configuration.t()}
  defstruct configuration: %Configuration{}

  @spec init(keyword()) :: {:ok, t()} | {:error, term()}
  def init(opts \\ []) when is_list(opts) do
    with {:ok, configuration} <- configuration(Keyword.get(opts, :configuration)) do
      {:ok, %__MODULE__{configuration: configuration}}
    end
  end

  @spec request(Request.t(), t()) :: {:ok, binary(), t()} | {:error, term(), t()}
  def request(%Request{} = request, %__MODULE__{} = state) do
    packet =
      EncapsulationPacket.new(
        protocol_id: request.protocol_id,
        protocol_id_extension: request.protocol_id_extension,
        user_defined: request.user_defined,
        data: request.data_unit,
        header_octets: request.header_octets
      )

    with :ok <- validate_channel(request.sdlp_channel),
         :ok <- validate_meta(request.meta),
         {:ok, encoded} <- Codec.encode(packet, configuration: state.configuration) do
      {:ok, encoded, state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def request(value, %__MODULE__{} = state),
    do: {:error, {:invalid_encapsulation_service_request, value}, state}

  @spec ingest(binary(), term(), t(), map()) ::
          {:ok, Indication.t(), t()} | {:error, term(), t()}
  def ingest(packet, sdlp_channel, %__MODULE__{} = state, meta \\ %{})
      when is_binary(packet) do
    with :ok <- validate_channel(sdlp_channel),
         :ok <- validate_meta(meta),
         {:ok, decoded} <- Codec.decode(packet, configuration: state.configuration) do
      {:ok,
       %Indication{
         data_unit: decoded.data,
         sdlp_channel: sdlp_channel,
         protocol_id: decoded.protocol_id,
         protocol_id_extension: decoded.protocol_id_extension,
         user_defined: decoded.user_defined,
         header_octets: decoded.header_octets,
         meta: meta
       }, state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp configuration(nil), do: {:ok, %Configuration{}}

  defp configuration(%Configuration{} = configuration) do
    case Configuration.validate(configuration) do
      :ok -> {:ok, configuration}
      {:error, _reason} = error -> error
    end
  end

  defp configuration(attrs) when is_map(attrs) or is_list(attrs), do: Configuration.new(attrs)
  defp configuration(value), do: {:error, {:invalid_encapsulation_configuration, value}}

  defp validate_channel(nil), do: {:error, :missing_sdlp_channel}
  defp validate_channel(_channel), do: :ok

  defp validate_meta(meta) when is_map(meta), do: :ok
  defp validate_meta(value), do: {:error, {:invalid_field, :meta, value}}
end
