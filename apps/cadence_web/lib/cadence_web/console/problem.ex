defmodule CadenceWeb.Console.Problem do
  @moduledoc """
  The console API error envelope: `{"error": {"code", "message", "details"?}}`.

  Codes are stable snake_case strings the SPA can switch on; messages are
  human-readable and may change.
  """

  import Plug.Conn

  @known %{
    unauthenticated: {401, "Sign in to continue."},
    invalid_csrf: {403, "The request CSRF token is invalid. Reload the page and try again."},
    forbidden: {403, "You do not have permission to do that."},
    scope_mismatch: {403, "That resource belongs to a different organization."},
    not_found: {404, "Not found."},
    mission_not_found: {404, "Mission not found."},
    organization_not_found: {404, "Organization not found."},
    spacecraft_not_found: {404, "Spacecraft not found."},
    profile_not_found: {404, "Profile not found."},
    transport_not_found: {404, "Transport not found."},
    plan_not_found: {404, "Contact plan not found."},
    import_run_not_found: {404, "Import run not found."},
    command_not_found: {404, "Command not found."},
    episode_not_found: {404, "Alarm not found."},
    episode_cleared: {409, "That alarm has already cleared."},
    note_required: {422, "A note is required."},
    assignee_not_member: {422, "That person isn't a member of this organization."},
    unsupported_format: {422, "That file format isn't supported."},
    file_too_large: {413, "The file is larger than 50 MiB."},
    import_failed: {422, "The import could not be started."},
    already_member: {409, "That person is already a member."},
    already_invited: {409, "That person already has a pending invitation."},
    invalid_params: {422, "The request parameters are invalid."},
    history_unavailable: {503, "Telemetry history is unavailable right now."},
    catalog_unavailable: {503, "The command catalog is unavailable right now."},
    alarms_unavailable: {503, "Alarms are unavailable right now."}
  }

  @doc "Sends the error envelope for a known reason atom and halts."
  @spec respond(Plug.Conn.t(), atom(), map() | nil) :: Plug.Conn.t()
  def respond(conn, reason, details \\ nil) when is_atom(reason) do
    {status, code, message} = describe(reason)

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(body(code, message, details))
    |> halt()
  end

  @doc "Returns `{status, code, message}` for a reason; unknown reasons are 422."
  @spec describe(atom()) :: {pos_integer(), binary(), binary()}
  def describe(reason) when is_atom(reason) do
    case Map.fetch(@known, reason) do
      {:ok, {status, message}} -> {status, Atom.to_string(reason), message}
      :error -> {422, Atom.to_string(reason), "The request could not be completed."}
    end
  end

  @spec body(binary(), binary(), map() | nil) :: map()
  def body(code, message, nil), do: %{error: %{code: code, message: message}}

  def body(code, message, details),
    do: %{error: %{code: code, message: message, details: details}}
end
