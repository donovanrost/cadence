defmodule CadenceWeb.Console.SpacecraftWorkspaceController do
  @moduledoc """
  (B) a spacecraft's configuration workspace (director 11-17; ux U94), under
  `/api/console/v1/missions/:mission_id/spacecraft/:spacecraft_id/configuration/workspace`.
  Contract: docs/apogee/api/setup.md §Spacecraft configuration workspace.

  Over the host's read model, Drafts and Control.SpacecraftConfiguration; no new domain logic.
  Approve and reject stay on L10 (the activation requests).
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Control.SpacecraftConfiguration, as: Control
  alias Cadence.Reads.Spacecraft.Configuration
  alias Cadence.Reads.Spacecraft.ConfigurationCatalogs
  alias CadenceWeb.Console.{ConfigJSON, Problem, SpacecraftWorkspaceJSON}

  @switch_words "Change this with a change set, from the spacecraft's Operation panel."
  @switches_refused "Not saved: Telemetry and Commanding are changed with a change set, not in a spacecraft's configuration."

  def show(conn, %{"spacecraft_id" => id} = params),
    do: respond_snapshot(conn, id, Map.get(params, "section", "overview"))

  def save_draft(
        conn,
        %{"spacecraft_id" => id, "token" => token, "document" => document} = params
      )
      when is_binary(token) and is_map(document) do
    case Enum.filter(SpacecraftWorkspaceJSON.switch_keys(), &Map.has_key?(document, &1)) do
      [] ->
        # Drafts.save takes the craft's own switches and ignores these (#109's backstop).
        input =
          Map.merge(document, %{"telemetry_enabled" => false, "commanding_enabled" => false})

        case Drafts.save(scope(conn), mission_id(conn), id, token, input) do
          {:ok, _row} -> respond_snapshot(conn, id, Map.get(params, "section", "overview"))
          {:error, reason} -> error(conn, reason)
        end

      keys ->
        details = Map.new(keys, &{"document." <> &1, @switch_words})

        conn
        |> put_status(422)
        |> json(Problem.body("invalid_params", @switches_refused, details))
    end
  end

  def save_draft(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{"document" => "Send token and document."})

  def submit(
        conn,
        %{"spacecraft_id" => id, "token" => token, "policy_token" => policy, "intent" => intent}
      )
      when is_binary(token) and is_binary(policy) and intent in ["review", "activate"] do
    intent = if intent == "review", do: :review, else: :activate

    case Control.submit(scope(conn), mission_id(conn), id, token, policy, intent) do
      {:ok, result} -> json(conn, %{data: SpacecraftWorkspaceJSON.submit_result(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def submit(conn, _params),
    do:
      Problem.respond(conn, :invalid_params, %{
        "intent" => "Send token, policy_token and intent (review or activate)."
      })

  def packets(conn, %{"spacecraft_id" => id, "catalog_revision_id" => catalog_id}) do
    case ConfigurationCatalogs.packets(scope(conn), mission_id(conn), id, catalog_id) do
      {:ok, choices} ->
        json(conn, %{data: SpacecraftWorkspaceJSON.packets(choices)})

      {:error, :spacecraft_catalog_unavailable} ->
        Problem.respond(conn, :catalog_revision_not_found)

      {:error, reason} ->
        error(conn, reason)
    end
  end

  defp respond_snapshot(conn, id, section) do
    case Configuration.load(scope(conn), conn.assigns.current_mission, id, section) do
      {:ok, snapshot} -> json(conn, %{data: SpacecraftWorkspaceJSON.snapshot(snapshot)})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, :invalid_spacecraft_section),
    do:
      Problem.respond(conn, :invalid_params, %{
        "section" => "One of overview, catalog, communications, changes."
      })

  defp error(conn, :invalid_spacecraft_configuration),
    do: Problem.respond(conn, :invalid_params, %{"document" => "Not a valid configuration."})

  defp error(conn, reason)
       when reason in [
              :forbidden,
              :scope_mismatch,
              :authenticated_user_required,
              :invalid_spacecraft_scope
            ],
       do: Problem.respond(conn, :forbidden)

  defp error(conn, reason) when is_atom(reason), do: Problem.respond(conn, reason)

  # U65: the model gate's refusal, named by catalog revision number (ConfigJSON's words).
  defp error(conn, {:mission_model_revision_not_approved, ids} = reason) when is_list(ids),
    do: ConfigJSON.error(conn, reason)

  defp error(conn, _reason), do: Problem.respond(conn, :invalid_params)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
