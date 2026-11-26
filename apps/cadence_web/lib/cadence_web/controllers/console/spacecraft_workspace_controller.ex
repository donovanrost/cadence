defmodule CadenceWeb.Console.SpacecraftWorkspaceController do
  @moduledoc """
  (B) a spacecraft's configuration workspace (director 11-17; ux U94), under
  `/api/v1/missions/:mission_id/spacecraft/:spacecraft_id/configuration/workspace`.
  Contract: docs/apogee/api/setup.md §Spacecraft configuration workspace.

  Over the host's read model, Drafts and Control.SpacecraftConfiguration; no new domain logic.
  Approve and reject stay on L10 (the activation requests).
  """

  use CadenceWeb, :controller

  require Logger

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Catalog
  alias Cadence.Control.SpacecraftConfiguration, as: Control
  alias Cadence.Reads.ModelApplyRefusals
  alias Cadence.Reads.Spacecraft.Configuration
  alias Cadence.Reads.Spacecraft.ConfigurationCatalogs
  alias Cadence.SpacecraftStore
  alias CadenceWeb.Console.{Problem, SpacecraftWorkspaceJSON, SpacecraftWorkspaceWords}

  @switch_words "Change this with a change set, from the spacecraft's Operation panel."
  @sections "One of overview, catalog, communications, changes."
  @switches_refused "Not saved: Telemetry and Commanding are changed with a change set, not in a spacecraft's configuration."

  def show(conn, %{"spacecraft_id" => id} = params),
    do: respond_snapshot(conn, id, Map.get(params, "section", "overview"), :show)

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
          {:ok, _row} -> respond_snapshot(conn, id, Map.get(params, "section", "overview"), :save)
          {:error, reason} -> error(conn, reason, :save, id)
        end

      keys ->
        details = Map.new(keys, &{"document." <> &1, @switch_words})

        conn
        |> put_status(422)
        |> json(Problem.body("invalid_params", @switches_refused, details))
    end
  end

  def save_draft(conn, params),
    do:
      refuse(conn, :invalid_params, :save, params["spacecraft_id"], %{
        "document" => "Send token and document."
      })

  def submit(
        conn,
        %{"spacecraft_id" => id, "token" => token, "policy_token" => policy, "intent" => intent}
      )
      when is_binary(token) and is_binary(policy) and intent in ["review", "activate"] do
    intent = if intent == "review", do: :review, else: :activate

    case Control.submit(scope(conn), mission_id(conn), id, token, policy, intent) do
      {:ok, result} -> json(conn, %{data: SpacecraftWorkspaceJSON.submit_result(result)})
      {:error, reason} -> error(conn, reason, :submit, id)
    end
  end

  def submit(conn, params),
    do:
      refuse(conn, :invalid_params, :submit, params["spacecraft_id"], %{
        "intent" => "Send token, policy_token and intent (review or activate)."
      })

  def packets(conn, %{"spacecraft_id" => id, "catalog_revision_id" => catalog_id}) do
    case ConfigurationCatalogs.packets(scope(conn), mission_id(conn), id, catalog_id) do
      {:ok, choices} ->
        json(conn, %{data: SpacecraftWorkspaceJSON.packets(choices)})

      {:error, :spacecraft_catalog_unavailable} ->
        refuse(conn, :catalog_revision_not_found, :packets, id)

      {:error, reason} ->
        error(conn, reason, :packets, id)
    end
  end

  defp respond_snapshot(conn, id, section, action) do
    case Configuration.load(scope(conn), conn.assigns.current_mission, id, section) do
      {:ok, snapshot} -> json(conn, %{data: SpacecraftWorkspaceJSON.snapshot(snapshot)})
      {:error, reason} -> error(conn, reason, action, id)
    end
  end

  defp error(conn, :invalid_spacecraft_section, action, id),
    do: refuse(conn, :invalid_params, action, id, %{"section" => @sections})

  defp error(conn, :invalid_spacecraft_configuration, action, id),
    do:
      refuse(
        conn,
        :invalid_params,
        action,
        id,
        %{"document" => "Not a valid configuration."},
        :invalid_document
      )

  defp error(conn, reason, action, id)
       when reason in [
              :forbidden,
              :scope_mismatch,
              :authenticated_user_required,
              :invalid_spacecraft_scope
            ],
       do: refuse(conn, :forbidden, action, id)

  # U65: the model gate names the unapproved model revisions; the words name catalog revisions.
  defp error(conn, {:mission_model_revision_not_approved, ids}, action, id) when is_list(ids) do
    numbers = ModelApplyRefusals.numbers(scope(conn).organization_id, mission_id(conn), ids)

    details = %{
      mission_model_revision_ids: ids,
      catalog_revision_numbers: Enum.map(ids, &numbers[&1])
    }

    ctx = %{catalog: SpacecraftWorkspaceWords.catalog_label(Enum.map(ids, &numbers[&1]))}
    refuse(conn, :mission_model_revision_not_approved, action, id, details, nil, ctx)
  end

  # #534: another generation saved a packet definition under the same version at the same moment.
  # Nothing was sent; sending again re-resolves (mms-ux's words; the id and version are details).
  defp error(
         conn,
         {:packet_definition_content_changed, packet_definition_id, version},
         action,
         id
       ),
       do:
         refuse(conn, :packet_definition_version_taken, action, id, %{
           packet_definition_id: packet_definition_id,
           version: version,
           retryable: true
         })

  defp error(conn, reason, action, id) when is_atom(reason), do: refuse(conn, reason, action, id)

  defp error(conn, reason, action, id) do
    Logger.warning("Spacecraft workspace #{action} refused: #{inspect(reason)}")
    refuse(conn, :invalid_params, action, id)
  end

  # The console's envelope with ux's U94 words where they exist (SpacecraftWorkspaceWords), else
  # the shared Problem message. `words` names the sentence when it isn't the code's own.
  defp refuse(conn, code, action, id, details \\ nil, words \\ nil, ctx \\ nil) do
    {status, code_string, default} = Problem.describe(code)
    ctx = ctx || context(conn, code, id)
    message = SpacecraftWorkspaceWords.message(words || code, action, ctx) || default

    conn
    |> put_status(status)
    |> json(Problem.body(code_string, message, details))
    |> halt()
  end

  # The craft's name for the words (never an id); the draft's catalog revision for the model gate.
  defp context(conn, code, id) do
    name =
      case SpacecraftStore.fetch_spacecraft(scope(conn).organization_id, mission_id(conn), id) do
        {:ok, craft} -> craft.display_name
        {:error, _} -> nil
      end

    %{
      name: name,
      catalog: if(code == :mission_model_revision_not_approved, do: draft_catalog(conn, id))
    }
  end

  defp draft_catalog(conn, id) do
    with %{document: %{"catalog_revision_id" => catalog_id}} when is_binary(catalog_id) <-
           Drafts.latest(scope(conn).organization_id, mission_id(conn), id),
         {:ok, revision} <-
           Catalog.fetch_revision(scope(conn).organization_id, mission_id(conn), catalog_id) do
      SpacecraftWorkspaceWords.catalog_label([revision.revision_number])
    else
      _ -> nil
    end
  end

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
