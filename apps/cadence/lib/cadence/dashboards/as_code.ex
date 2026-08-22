defmodule Cadence.Dashboards.AsCode do
  @moduledoc "CI-facing validation for raw Dashboard Documents and governed export bundles."

  alias Cadence.Dashboards.{Contracts, Document, DocumentCodec, ValidationResult}

  @spec validate_file(Path.t()) :: {:ok, map()} | {:error, map()}
  def validate_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, json} -> validate_content(json, path)
      {:error, reason} -> {:error, %{path: path, stage: :read, reason: reason}}
    end
  end

  @spec validate_content(binary(), binary()) :: {:ok, map()} | {:error, map()}
  def validate_content(json, source \\ "inline") when is_binary(json) and is_binary(source) do
    with {:ok, %Document{} = document} <- DocumentCodec.decode_import(json),
         %ValidationResult{valid?: true} = validation <- Contracts.validate_document(document) do
      {:ok,
       %{
         source: source,
         dashboard_id: document.dashboard_id,
         name: document.name,
         schema_version: document.schema_version,
         warnings: validation.warnings
       }}
    else
      %ValidationResult{} = validation ->
        {:error, %{path: source, stage: :document_contract, reason: validation.errors}}

      {:error, reason} ->
        {:error, %{path: source, stage: :decode_or_integrity, reason: reason}}
    end
  end
end
