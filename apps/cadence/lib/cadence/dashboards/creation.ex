defmodule Cadence.Dashboards.Creation do
  @moduledoc "Scoped blank, clone and import creation independent of frontend delivery."
  require Logger

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Dashboards.{
    AuthoringDefaults,
    CurrentVersions,
    Document,
    DocumentCodec,
    Documents
  }

  alias Cadence.{Missions, SpacecraftStore}

  def authorize(
        %Scope{organization_id: org, mission_id: scoped, user: %{user_id: user}} = scope,
        mission
      )
      when is_binary(org) and org != "" and is_binary(mission) and mission != "" and
             is_binary(user) and user != "" and (is_nil(scoped) or scoped == mission) do
    with :ok <-
           Policy.authorize(scope, :author_dashboards, %{
             organization_id: org,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(org, mission),
         do: :ok
  end

  def authorize(_, _), do: {:error, :forbidden}

  def create(scope, mission, model, input) do
    with :ok <- authorize(scope, mission),
         {:ok, fields} <- fields(input, model.mode),
         {:ok, document} <- document(scope, mission, model, fields) do
      case CurrentVersions.create(scope.organization_id, document, created_by: scope.user.user_id) do
        {:ok, saved} ->
          {:ok,
           %{dashboard_id: saved.dashboard_id, version: Document.version(saved), mode: model.mode}}

        # Creating publishes the first version: a readiness failure says what to fix.
        {:error, {:invalid_dashboard_document, _result}} = not_ready ->
          not_ready

        error ->
          Logger.warning("dashboard creation failed: #{inspect(error, limit: 20)}")
          {:error, :unknown}
      end
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  # A new (blank) dashboard may also carry `tags` and a `spacecraft` default (console D4); the
  # other modes take exactly their keys.
  defp fields(input, mode) when is_map(input) and map_size(input) <= 5 do
    keys = if mode == "import", do: ~w(name description document_json), else: ~w(name description)
    optional = if mode == "new", do: ~w(tags spacecraft), else: []

    with true <- Enum.sort(Map.keys(input) -- optional) == Enum.sort(keys),
         true <- text?(input["name"], 512) and String.trim(input["name"]) != "",
         true <- text?(input["description"], 4096),
         true <- mode != "import" or text?(input["document_json"], 262_144),
         {:ok, tags} <- tags(Map.get(input, "tags", [])),
         {:ok, spacecraft} <- spacecraft(Map.get(input, "spacecraft")) do
      {:ok,
       %{
         name: String.trim(input["name"]),
         description: String.trim(input["description"]),
         json: input["document_json"],
         tags: tags,
         spacecraft_id: spacecraft
       }}
    else
      _ -> {:invalid, :fields}
    end
  end

  defp fields(_, _), do: {:invalid, :fields}

  defp tags(tags) when is_list(tags) and length(tags) <= 10 do
    trimmed = tags |> Enum.filter(&text?(&1, 64)) |> Enum.map(&String.trim/1)

    if length(trimmed) == length(tags) and "" not in trimmed,
      do: {:ok, Enum.uniq(trimmed)},
      else: :error
  end

  defp tags(_tags), do: :error

  # `fixed` sets the document's default scope to that spacecraft; `context` and `fleet` (the
  # viewer picks, or constellation-wide widgets) set none.
  defp spacecraft(nil), do: {:ok, nil}

  defp spacecraft(%{"mode" => mode} = input)
       when mode in ~w(context fleet) and map_size(input) == 1,
       do: {:ok, nil}

  defp spacecraft(%{"mode" => "fixed", "spacecraft_id" => id} = input)
       when map_size(input) == 2 and is_binary(id) and byte_size(id) in 1..256,
       do: {:ok, id}

  defp spacecraft(_input), do: :error

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value)

  defp document(scope, mission, %{mode: "new"}, fields) do
    with {:ok, defaults} <- defaults(scope, mission, fields.spacecraft_id) do
      {:ok, blank(scope, mission, fields, defaults)}
    end
  end

  defp document(scope, mission, %{mode: "clone", source: source}, fields) do
    case Documents.fetch_for_mode(scope.organization_id, mission, source.id, :edit) do
      {:ok, document} ->
        if Document.version(document) == source.version,
          do: {:ok, copy(document, scope, mission, fields, "dashboard_clone")},
          else: {:invalid, :source_changed}

      _ ->
        {:invalid, :source_changed}
    end
  end

  defp document(scope, mission, %{mode: "import"}, fields) do
    case DocumentCodec.decode_import(fields.json) do
      {:ok, document} -> {:ok, copy(document, scope, mission, fields, "dashboard_import")}
      _ -> {:invalid, :document}
    end
  end

  defp document(_, _, _, _), do: {:invalid, :fields}

  defp defaults(_scope, _mission, nil), do: {:ok, %{}}

  # The same scope OpsWorkspaceURL admits for one spacecraft; it must be this mission's.
  defp defaults(scope, mission, spacecraft_id) do
    owned? =
      match?(
        {:ok, _},
        SpacecraftStore.fetch_spacecraft(scope.organization_id, mission, spacecraft_id)
      )

    defaults = %{
      "scope" => %{
        "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => [spacecraft_id]},
        "spacecraft_id" => spacecraft_id
      }
    }

    if owned? and AuthoringDefaults.validate(defaults) == :ok,
      do: {:ok, defaults},
      else: {:invalid, :spacecraft}
  end

  defp blank(scope, mission, fields, defaults) do
    %Document{
      dashboard_id: Cadence.Ids.new("ops_dashboard"),
      organization_id: scope.organization_id,
      mission_id: mission,
      name: fields.name,
      description: fields.description,
      defaults: defaults,
      metadata:
        %{"source" => "dashboard_creation", "created_by" => scope.user.user_id}
        |> put_tags(fields.tags)
    }
  end

  defp put_tags(metadata, []), do: metadata
  defp put_tags(metadata, tags), do: Map.put(metadata, "tags", tags)

  defp copy(document, scope, mission, fields, source) do
    DocumentCodec.copy_for_scope(document, scope.organization_id, mission,
      name: fields.name,
      description: fields.description,
      source: source,
      source_dashboard_id: document.dashboard_id,
      actor_id: scope.user.user_id
    )
  end
end
