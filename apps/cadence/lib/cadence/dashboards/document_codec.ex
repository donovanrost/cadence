defmodule Cadence.Dashboards.DocumentCodec do
  @moduledoc """
  Serialization, migration, and scope-safe copying for dashboard documents.
  """

  alias Cadence.Dashboards.{Document, DocumentMigration}

  @spec decode!(binary()) :: Document.t()
  def decode!(json) when is_binary(json) do
    case json |> Jason.decode!() |> DocumentMigration.migrate_map() do
      {:ok, %DocumentMigration.Result{document: document}} ->
        document

      {:error, reason} ->
        raise ArgumentError, "invalid dashboard document: #{inspect(reason)}"
    end
  end

  @spec decode(binary()) :: {:ok, Document.t()} | {:error, term()}
  def decode(json) when is_binary(json) do
    with {:ok, attrs} when is_map(attrs) <- Jason.decode(json),
         {:ok, %DocumentMigration.Result{document: document}} <-
           DocumentMigration.migrate_map(attrs) do
      {:ok, document}
    else
      {:ok, _not_a_document} -> {:error, :dashboard_document_must_be_an_object}
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_dashboard_json, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec encode(Document.t()) :: {:ok, binary()} | {:error, term()}
  def encode(%Document{} = document) do
    document |> Document.to_map() |> Jason.encode(pretty: true)
  end

  @spec encode_bundle(Document.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode_bundle(%Document{} = document, opts \\ []) do
    document_map = Document.to_map(document)

    %{
      "schema" => "cadence.dashboard_export.v1",
      "exported_at" => DateTime.to_iso8601(Keyword.get(opts, :exported_at, DateTime.utc_now())),
      "exported_by" => Keyword.get(opts, :exported_by),
      "binding_semantics_sha256" => binding_semantics_sha256(document_map),
      "policy" => %{
        "identity_on_import" => "replace_with_target_scope",
        "secrets_included" => false,
        "runtime_data_included" => false
      },
      "document" => document_map
    }
    |> Jason.encode(pretty: true)
  end

  @spec decode_import(binary()) :: {:ok, Document.t()} | {:error, term()}
  def decode_import(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"schema" => "cadence.dashboard_export.v1"} = bundle} ->
        decode_bundle(bundle)

      {:ok, _document_or_other} ->
        decode(json)

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_dashboard_json, error}}
    end
  end

  @spec load!(Path.t()) :: Document.t()
  def load!(path) when is_binary(path), do: path |> File.read!() |> decode!()

  @spec migrate_map(map()) :: DocumentMigration.result()
  def migrate_map(attrs) when is_map(attrs), do: DocumentMigration.migrate_map(attrs)

  @spec copy_for_scope(Document.t(), binary(), binary(), keyword()) :: Document.t()
  def copy_for_scope(%Document{} = source, organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    metadata =
      source.metadata
      |> ensure_metadata()
      |> Map.drop([:version, "version", :dashboard_version, "dashboard_version"])
      |> Map.put("source", Keyword.fetch!(opts, :source))
      |> maybe_put_metadata("source_dashboard_id", Keyword.get(opts, :source_dashboard_id))
      |> maybe_put_metadata("created_by", Keyword.get(opts, :actor_id))

    %Document{
      source
      | dashboard_id: Cadence.Ids.new("ops_dashboard"),
        organization_id: organization_id,
        mission_id: mission_id,
        name: Keyword.fetch!(opts, :name),
        description: Keyword.get(opts, :description),
        metadata: metadata
    }
  end

  defp decode_bundle(bundle) do
    document_attrs = bundle["document"]
    expected = bundle["binding_semantics_sha256"]

    cond do
      not is_map(document_attrs) ->
        {:error, :dashboard_export_missing_document}

      not is_binary(expected) ->
        {:error, :dashboard_export_missing_binding_semantics}

      expected != binding_semantics_sha256(document_attrs) ->
        {:error, :dashboard_export_binding_semantics_mismatch}

      true ->
        case DocumentMigration.migrate_map(document_attrs) do
          {:ok, %DocumentMigration.Result{document: document}} -> {:ok, document}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp binding_semantics_sha256(document_attrs) do
    document_attrs
    |> binding_semantics()
    |> canonical_term()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp binding_semantics(document_attrs) do
    %{
      "schema_version" => map_value(document_attrs, :schema_version),
      "defaults" => map_value(document_attrs, :defaults) || %{},
      "placements" =>
        document_attrs
        |> map_value(:placements)
        |> List.wrap()
        |> Enum.map(fn placement ->
          %{
            "placement_id" => map_value(placement, :placement_id),
            "content" => map_value(placement, :content) || %{},
            "scope_override" => map_value(placement, :scope_override),
            "data_override" => map_value(placement, :data_override),
            "limit_override" => map_value(placement, :limit_override),
            "repeat" => map_value(placement, :repeat)
          }
        end)
    }
  end

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical_term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)
  defp canonical_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp canonical_term(value), do: value
  defp map_value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp ensure_metadata(metadata) when is_map(metadata), do: metadata
  defp ensure_metadata(_metadata), do: %{}
  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
