defmodule CadenceWeb.Console.CatalogImportController do
  @moduledoc """
  Catalog uploads (C2): `POST .../catalog/imports` (multipart) and
  `GET .../catalog/importers`. Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Catalog.{ImportRun, Registry, Upload}
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def importers(conn, _params) do
    json(conn, %{data: %{importers: importer_list(), max_bytes: Upload.max_bytes()}})
  end

  def create(conn, %{"file" => %Plug.Upload{} = file} = params) do
    database_id = blank_to_nil(params["database_id"])
    fields = Map.take(params, Upload.fields(database_id))

    with {:ok, bytes} <- read(file),
         {:ok, %ImportRun{} = run} <-
           Upload.import_revision(
             conn.assigns.current_scope,
             conn.assigns.current_mission.mission_id,
             database_id,
             Map.merge(%{"revision_label" => "", "revision_notes" => ""}, fields),
             %{filename: file.filename, bytes: bytes, client_type: file.content_type}
           ) do
      conn
      |> put_status(:accepted)
      |> json(%{data: %{import_run_id: run.import_run_id}})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def create(conn, _params), do: Problem.respond(conn, :invalid_params, %{file: "is required"})

  defp read(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size > 0 ->
        if size > Upload.max_bytes(), do: {:error, :file_too_large}, else: File.read(path)

      _empty ->
        {:error, %{"file" => "The file is empty."}}
    end
  end

  defp error(conn, details) when is_map(details) and not is_struct(details),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, :no_matching_importer),
    do: Problem.respond(conn, :unsupported_format, %{accepted: importer_list()})

  defp error(conn, reason) when reason in [:invalid_catalog_upload, :invalid_catalog_filename],
    do:
      Problem.respond(conn, :invalid_params, %{
        file: "Choose a catalog file (a valid file name, at most 50 MiB)."
      })

  defp error(conn, :file_too_large), do: Problem.respond(conn, :file_too_large)
  defp error(conn, :forbidden), do: Problem.respond(conn, :forbidden)

  defp error(conn, %Ecto.Changeset{} = changeset),
    do: Problem.respond(conn, :invalid_params, changeset_errors(changeset))

  defp error(conn, _reason), do: Problem.respond(conn, :import_failed)

  defp importer_list do
    Enum.map(Cadence.Catalog.list_importers(), fn %{descriptor: descriptor} ->
      %{
        key: descriptor.importer_key,
        label: descriptor.display_name,
        extensions: Registry.extensions(descriptor)
      }
    end)
  end

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> ConfigJSON.encode()
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
