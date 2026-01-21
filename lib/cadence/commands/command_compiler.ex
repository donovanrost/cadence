defmodule Cadence.Commands.CommandCompiler do
  @moduledoc """
  Command compilation utilities for building uplink PDUs.

  Performs command lookup, argument validation, binary encoding,
  and PDU wrapping for uplink dispatch.
  """

  require Logger

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.Commands
  alias Cadence.Commands.{Encoder, PDUBuilder}
  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Ports.Repository.Commanding.CommandsRepository
  alias Cadence.Runtime.Commands.MetaCommandCache

  @type compile_result ::
          {:ok, %{command: MetaCommand.t(), encoded: binary(), pdu: PDU.t()}}
          | {:error, term()}

  @spec fetch_command(String.t(), String.t(), String.t()) ::
          {:ok, MetaCommand.t()} | {:error, :unknown_command}
  def fetch_command(mission_id, definition_set_id, command_name) do
    Logger.debug(
      "[GET_COMMAND] Looking up command_name=#{inspect(command_name)} " <>
        "for definition_set_id=#{inspect(definition_set_id)}"
    )

    case MetaCommandCache.get_by_name(mission_id, definition_set_id, command_name) do
      {:ok, command} ->
        Logger.debug("[GET_COMMAND] FOUND in cache - command id=#{command.id}")
        {:ok, command}

      {:error, reason} when reason in [:not_found, :cache_not_available] ->
        if reason == :cache_not_available do
          Logger.debug("[GET_COMMAND] Cache not available, falling back to database")
        else
          Logger.debug("[GET_COMMAND] Cache miss, falling back to database")
        end

        fetch_from_repo(definition_set_id, command_name)
    end
  end

  @spec compile(MetaCommand.t(), map(), map(), String.t()) :: compile_result()
  def compile(%MetaCommand{} = command, params, target, aggregate_id) when is_map(params) do
    with :ok <- validate_args(command, params),
         {:ok, encoded} <- encode_command(command, params),
         {:ok, pdu} <- build_pdu(encoded, target, aggregate_id, command.name) do
      {:ok, %{command: command, encoded: encoded, pdu: pdu}}
    else
      {:error, _} = error -> error
      {:error, _, _} = error -> error
    end
  end

  defp fetch_from_repo(definition_set_id, command_name) do
    case Commands.get_meta_command(definition_set_id, command_name) do
      nil ->
        Logger.warning(
          "[GET_COMMAND] NOT FOUND - definition_set_id=#{inspect(definition_set_id)}, " <>
            "command_name=#{inspect(command_name)}"
        )

        {:error, :unknown_command}

      command ->
        Logger.debug("[GET_COMMAND] FOUND in database - command id=#{command.id}")

        {:ok,
         CommandsRepository.impl().ensure_loaded(command,
           associations: [:arguments, :verifiers, :transmission_constraints]
         )}
    end
  end

  defp validate_args(command, params) do
    case Commands.validate_arguments(command, params) do
      :ok -> :ok
      {:error, errors} -> {:error, :validation_failed, errors}
    end
  end

  defp encode_command(command, params) do
    case Encoder.encode(command, params) do
      {:ok, binary} -> {:ok, binary}
      {:error, reason} -> {:error, :encoding_failed, reason}
    end
  end

  defp build_pdu(encoded, target, aggregate_id, command_name) do
    meta = %{
      command_aggregate_id: aggregate_id,
      command_name: command_name,
      target_id: target.id
    }

    PDUBuilder.build(encoded, target, meta)
  end
end
