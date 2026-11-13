defmodule Cadence.Reads.AppStatus do
  @moduledoc """
  One application's status at one host scope, for the console Apps list (A1) and the surface
  host (§11 L9): `%{state, label, version}`.

  - `active`: a platform app, or installed and its status loads.
  - `not_installed`: no installation row, or uninstalled. `disabled`: installed then disabled.
  - `activation_pending`: installed with an approval-pending activation request for its binding
    set (only telemetry decom requests activation today; L10 approves it).
  - `failed`: installed but its status can't be loaded.

  `label` is the app's own status words (`Cadence.Applications.Status.label`, e.g. "Monitoring")
  or nil; `version` is the installed version (the definition's for a platform app). While
  `activation_pending`, `activation_request` is `%{requested_by: %{name} | nil, requested_at}`
  (ux #77: "requested by Mira K. at 02:10Z"). Callers authorize first; the status providers
  authorize again.
  """

  alias Cadence.Accounts

  alias Cadence.Applications.{ApplicationDefinition, HostContext, TelemetryDecom}
  alias Cadence.Auth.Scope
  alias Cadence.Management.Activations
  alias Cadence.Reads.Applications

  @type t :: %{state: atom(), label: binary() | nil, version: binary() | nil}

  @spec status(Scope.t(), ApplicationDefinition.t(), struct() | nil, HostContext.t()) :: t()
  def status(%Scope{} = scope, %ApplicationDefinition{} = definition, installation, host_context) do
    cond do
      definition.installation_policy == :platform ->
        loaded(scope, definition, host_context, :active, definition.version)

      is_nil(installation) or installation.lifecycle_state == :uninstalled ->
        %{state: :not_installed, label: nil, version: nil}

      installation.lifecycle_state == :disabled ->
        %{state: :disabled, label: nil, version: installation.application_version}

      true ->
        installed(scope, definition, host_context, installation.application_version)
    end
  end

  defp installed(scope, definition, host_context, version) do
    case pending_request(scope, definition, host_context) do
      %{} = request ->
        scope
        |> loaded(definition, host_context, :activation_pending, version)
        |> Map.put(:activation_request, %{
          requested_by: requester(request),
          requested_at: request.requested_at
        })

      nil ->
        loaded(scope, definition, host_context, :active, version)
    end
  end

  defp requester(%{requester_actor_kind: kind, requester_actor_id: id})
       when kind in [:user, "user"] and is_binary(id) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> %{name: user.display_name || user.email}
      _missing -> nil
    end
  end

  defp requester(_request), do: nil

  defp loaded(scope, definition, host_context, state, version) do
    case Applications.load_status(scope, definition, host_context) do
      {:ok, status} -> %{state: state, label: status.label, version: version}
      {:error, _unavailable} -> %{state: :failed, label: nil, version: version}
    end
  end

  # The mission-wide binding set's pending request belongs to telemetry decom today
  # (TelemetryDecom.binding_set_id/1); other apps don't request activation.
  defp pending_request(scope, %ApplicationDefinition{application_key: key}, %HostContext{
         mission_id: mission_id
       })
       when is_binary(mission_id) do
    with true <- key == TelemetryDecom.application_key(),
         {:ok, %{} = request} <-
           Activations.latest_pending(
             scope,
             mission_id,
             TelemetryDecom.binding_set_id(mission_id)
           ) do
      request
    else
      _none -> nil
    end
  end

  defp pending_request(_scope, _definition, _host_context), do: nil
end
