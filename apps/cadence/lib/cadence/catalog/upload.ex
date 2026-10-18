defmodule Cadence.Catalog.Upload do
  @moduledoc "Authorized, atomic creation of a database revision from bounded upload bytes."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, Registry}
  alias Cadence.Missions
  alias Cadence.Repo

  @max_bytes 52_428_800
  def max_bytes, do: @max_bytes

  def fields(database_id),
    do:
      if(is_nil(database_id),
        do: ~w(name revision_label revision_notes),
        else: ~w(revision_label revision_notes)
      )

  def validate(database_id, params) when is_map(params) do
    values = Map.take(params, fields(database_id))

    errors =
      Enum.reduce(fields(database_id), %{}, fn key, errors ->
        value = Map.get(values, key, "")
        limit = if key == "revision_notes", do: 4096, else: 255

        cond do
          not is_binary(value) or byte_size(value) > limit or not String.valid?(value) ->
            Map.put(errors, key, "Enter valid text within #{limit} bytes.")

          key == "name" and String.trim(value) == "" ->
            Map.put(errors, key, "Enter a database name.")

          true ->
            errors
        end
      end)

    if errors == %{}, do: {:ok, values}, else: {:error, errors}
  end

  def validate(_database_id, _params), do: {:error, %{"name" => "Invalid upload fields."}}

  def import_revision(%Scope{} = scope, mission_id, database_id, params, upload) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, values} <- validate(database_id, params),
         :ok <- validate_upload(upload),
         {:ok, %{descriptor: descriptor}} <-
           Registry.detect_importer(upload.filename, upload[:client_type]) do
      # The browser's media type is a detection hint, not the canonical format.
      artifact =
        Artifact.build_from_upload(mission_id, descriptor, Map.put(upload, :client_type, nil),
          uploaded_by: actor(scope)
        )

      Repo.transaction(fn ->
        create_import(scope, mission_id, database_id, values, descriptor, artifact)
      end)
    end
  end

  defp create_import(scope, mission_id, database_id, values, descriptor, artifact) do
    with {:ok, database} <- database(scope, mission_id, database_id, values, descriptor),
         {:ok, run} <-
           Catalog.start_revision_import(
             scope.organization_id,
             mission_id,
             database.catalog_database_id,
             artifact,
             descriptor.importer_key,
             requested_by: actor(scope),
             metadata: Map.take(values, ~w(revision_label revision_notes))
           ) do
      run
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp database(scope, mission_id, nil, values, descriptor) do
    Catalog.create_database(scope.organization_id, mission_id, %{
      name: String.trim(values["name"]),
      catalog_family: descriptor.catalog_family,
      default_importer_key: descriptor.importer_key,
      created_by: actor(scope)
    })
  end

  defp database(scope, mission_id, database_id, _values, _descriptor),
    do: Catalog.fetch_database(scope.organization_id, mission_id, database_id)

  defp validate_upload(%{filename: filename, bytes: bytes})
       when is_binary(filename) and is_binary(bytes) and byte_size(bytes) > 0 and
              byte_size(bytes) <= @max_bytes do
    if byte_size(filename) in 1..255 and String.valid?(filename) and
         not String.contains?(filename, ["/", "\\", "\r", "\n", <<0>>]),
       do: :ok,
       else: {:error, :invalid_catalog_filename}
  end

  defp validate_upload(_upload), do: {:error, :invalid_catalog_upload}
  defp actor(%Scope{user: %{id: id, email: email}}), do: %{user_id: id, email: email}
  defp actor(%Scope{}), do: %{}
end
