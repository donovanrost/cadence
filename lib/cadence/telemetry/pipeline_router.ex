defmodule Cadence.Telemetry.PipelineRouter do
  @moduledoc """
  Routes resolved packets to decom or explicit sinks.
  """

  alias Cadence.Telemetry.ResolvedUnit

  @type sink :: :unidentified | :unknown_schema | :unsupported_format | :malformed

  @spec route_resolved(ResolvedUnit.t()) ::
          {:decom, ResolvedUnit.t()} | {:sink, sink(), map()}
  def route_resolved(%ResolvedUnit{} = resolved) do
    case {resolved.format, resolved.identity, resolved.schema} do
      {:space_packet, {:ok, _target_id}, {:ok, _packet_def}} ->
        {:decom, resolved}

      {:space_packet, {:ok, _target_id}, {:unsupported_format, _}} ->
        {:sink, :unsupported_format, %{schema: resolved.schema}}

      {:space_packet, {:ok, _target_id}, _schema} ->
        {:sink, :unknown_schema, %{schema: resolved.schema}}

      {:space_packet, _identity, _schema} ->
        {:sink, :unidentified, %{identity: resolved.identity, schema: resolved.schema}}

      {:encap_packet, _identity, _schema} ->
        {:sink, :unsupported_format, %{schema: resolved.schema}}

      {:unknown, _identity, _schema} ->
        {:sink, :unsupported_format, %{schema: resolved.schema}}
    end
  end

  @spec route_parse_error(term()) :: {:sink, :malformed, map()}
  def route_parse_error(parse_error) do
    {:sink, :malformed, %{parse_error: parse_error}}
  end
end
