defmodule CadenceWeb.Console.SettingsController do
  @moduledoc """
  ST1 Settings for a mission (`/missions/:mission_id/settings`) or the
  organization (`/organizations/:organization_id/settings`). Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Management.ConsoleSettings
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, _params) do
    case ConsoleSettings.load(conn.assigns.current_scope, mission_id(conn)) do
      {:ok, data} -> json(conn, %{data: ConfigJSON.encode(data)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def update(conn, %{"section_key" => key} = params) do
    expected = if is_integer(params["expected_version"]), do: params["expected_version"]

    case ConsoleSettings.save(
           conn.assigns.current_scope,
           mission_id(conn),
           key,
           params["values"],
           expected
         ) do
      {:ok, result} -> conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(result)})
      {:error, reason} -> save_error(conn, key, reason)
    end
  end

  # #233 (ux U96): who may change the approval setting, in words chosen by the level saved.
  defp save_error(conn, _key, :approval_policy_change_requires_organization_admin),
    do: refuse(conn, :approval_policy_change_requires_organization_admin, approval_words(conn))

  # A mission admin saving the organization's approval setting (its scope is its mission's).
  defp save_error(conn, "cadence.governance", reason)
       when reason in [:forbidden, :scope_mismatch] do
    if mission_id(conn),
      do: error(conn, reason),
      else: refuse(conn, :forbidden, approval_words(conn))
  end

  defp save_error(conn, _key, reason), do: error(conn, reason)

  defp approval_words(conn) do
    case conn.assigns[:current_mission] do
      %{mission_id: _id, display_name: name} ->
        "Not saved: only an organization admin can let changes on #{name} apply without approval."

      _organization ->
        "Not saved: only an organization admin can change the organization's approval setting."
    end
  end

  defp refuse(conn, reason, message) do
    {status, code, _default} = Problem.describe(reason)

    conn
    |> put_status(status)
    |> json(Problem.body(code, message, nil))
    |> halt()
  end

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:version_conflict, current}),
    do: Problem.respond(conn, :version_conflict, %{expected_version: current})

  defp error(conn, :invalid_settings),
    do: Problem.respond(conn, :invalid_params, %{values: "is not a valid value for this section"})

  defp error(conn, :settings_changed), do: Problem.respond(conn, :version_conflict)

  defp error(conn, :unknown_settings_section),
    do: Problem.respond(conn, :settings_section_not_found)

  defp error(conn, reason)
       when reason in [:forbidden, :scope_mismatch, :authenticated_user_required],
       do: Problem.respond(conn, :forbidden)

  defp error(conn, reason) when is_atom(reason), do: Problem.respond(conn, reason)
  defp error(conn, _reason), do: Problem.respond(conn, :settings_write_unconfirmed)

  # Organization routes have no mission.
  defp mission_id(conn) do
    case conn.assigns[:current_mission] do
      %{mission_id: id} -> id
      _organization -> nil
    end
  end
end
