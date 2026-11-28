defmodule Cadence.Control.CommandEncodingPreview do
  @moduledoc """
  The bytes a command request would release (M24, Approve A3): the command's encoded payload,
  produced exactly as release produces it (`Commanding.release_command_queue_entry`): the
  request's own model revision basis (`RequestValidation.resolve_basis`) and its resolved
  argument values, through `Control.Commanding.encode_command`.

  It never encodes against another revision. When the request's revision isn't the active one
  any more, release would fail closed, and so does the preview (`:revision_not_active` /
  `:revision_superseded`). The bytes are the command payload before transport framing (no TC
  frame, segment or CLTU around it); nothing is transmitted.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Commanding
  alias Cadence.Commanding.RequestValidation
  alias Cadence.Control.Commanding, as: ControlCommanding
  alias Cadence.Management.Commanding, as: ManagementCommanding

  # todo(authz): Cedar should decide who may see encoded command bytes (today: anyone who may
  # review the mission's requests, :operate_mission since #62).
  @spec preview(Scope.t(), binary(), binary()) ::
          {:ok, map()}
          | {:error, :forbidden | :command_request_not_found}
          | {:error, {:encode_unavailable, atom(), binary() | nil}}
  def preview(%Scope{} = scope, mission_id, command_request_id) do
    organization_id = scope.organization_id

    with :ok <- authorize(scope, mission_id),
         {:ok, request} <- fetch(organization_id, mission_id, command_request_id),
         {:ok, basis} <- basis(organization_id, mission_id, request),
         {:ok, encoded} <- encode(basis, request) do
      {:ok,
       %{
         command_request_id: request.command_request_id,
         command_id: request.command_id,
         mission_model_revision_id: request.mission_model_revision_id,
         scope: "command_payload",
         size_bytes: encoded.size_bytes,
         hex: Base.encode16(encoded.binary, case: :upper),
         base64: encoded.base64,
         # JSON text so 64-bit values survive JavaScript (commanding.md "Argument values").
         arguments_json: Jason.encode!(request.resolved_argument_values || %{})
       }}
    end
  end

  defp authorize(scope, mission_id) do
    case ManagementCommanding.authorize(scope, mission_id) do
      {:ok, _fresh, _} -> :ok
      _denied -> {:error, :forbidden}
    end
  end

  defp fetch(organization_id, mission_id, command_request_id) do
    case Commanding.fetch_command_request(organization_id, mission_id, command_request_id) do
      {:ok, request} -> {:ok, request}
      _missing -> {:error, :command_request_not_found}
    end
  end

  defp basis(organization_id, mission_id, request) do
    case RequestValidation.resolve_basis_of(organization_id, mission_id, request) do
      {:ok, basis} ->
        {:ok, basis}

      {:error, {:mission_model_revision_mismatch, _requested, active}} ->
        {:error, {:encode_unavailable, :revision_superseded, active}}

      {:error, {:mission_model_revision_not_active, _requested}} ->
        {:error, {:encode_unavailable, :revision_not_active, nil}}

      {:error, reason} ->
        {:error, {:encode_unavailable, :basis_unavailable, describe(reason)}}
    end
  end

  defp encode(basis, request) do
    case ControlCommanding.encode_command(
           basis.runtime_definition,
           request.resolved_argument_values || %{}
         ) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> {:error, {:encode_unavailable, :encode_failed, describe(reason)}}
    end
  end

  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(_reason), do: nil
end
