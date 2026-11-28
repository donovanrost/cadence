defmodule Cadence.Reads.ApplicationSurfaces.ReferenceResolver do
  @moduledoc """
  The host's registry of versioned surface reference providers.

  None is registered: the one surface that declared a reference, Telemetry Decom's Manage page,
  went when the application became headless (#669). `validate_providers/0` keeps it that way
  (every declared reference needs a registered provider and every provider a declared
  reference), and a surface form with a reference field is refused rather than rendered without
  its choices.
  """

  alias Cadence.Applications.{ApplicationDefinition, HostContext, Registry, SurfaceDocument}
  alias Cadence.Applications.SurfaceElements.GeneratedForm
  alias Cadence.Auth.Scope

  alias Cadence.Extensions.Presentation.{FieldDefinition, ReferenceDefinition}

  @spec validate_providers() ::
          :ok | {:error, :invalid_application_reference_provider_registry}
  def validate_providers, do: validate_providers(Registry.all(), %{})

  @doc false
  @spec validate_providers([ApplicationDefinition.t()], map()) ::
          :ok | {:error, :invalid_application_reference_provider_registry}
  def validate_providers(definitions, providers)
      when is_list(definitions) and is_map(providers) do
    required_identities =
      for definition <- definitions,
          surface <- definition.surfaces,
          {_field, %ReferenceDefinition{} = reference} <- surface.references,
          do: {reference.provider_id, reference.version}

    registered_identities =
      for {provider_id, versions} <- providers,
          is_map(versions),
          {version, _provider} <- versions,
          do: {provider_id, version}

    if same_identities?(required_identities, registered_identities) and
         valid_provider_modules?(providers) do
      :ok
    else
      {:error, :invalid_application_reference_provider_registry}
    end
  end

  def validate_providers(_definitions, _providers),
    do: {:error, :invalid_application_reference_provider_registry}

  @spec resolve(Scope.t(), HostContext.t(), SurfaceDocument.t()) ::
          {:ok, SurfaceDocument.t()} | {:error, term()}
  def resolve(
        %Scope{},
        %HostContext{},
        %SurfaceDocument{form: %GeneratedForm{fields: fields}} = document
      ) do
    case Enum.find_value(fields, &field_error/1) do
      nil -> {:ok, document}
      reason -> {:error, reason}
    end
  end

  def resolve(%Scope{}, %HostContext{}, %SurfaceDocument{} = document), do: {:ok, document}

  defp field_error(%FieldDefinition{type: :reference, reference: %ReferenceDefinition{}}),
    do: :unknown_reference_provider

  defp field_error(%FieldDefinition{type: :reference}), do: :invalid_reference_field

  defp field_error(%FieldDefinition{reference: reference}) when not is_nil(reference),
    do: :invalid_reference_field

  defp field_error(%FieldDefinition{}), do: nil

  defp valid_provider_modules?(providers) do
    Enum.all?(providers, fn {_provider_id, versions} ->
      is_map(versions) and
        Enum.all?(versions, fn {_version, provider} ->
          Code.ensure_loaded?(provider) and function_exported?(provider, :search, 5)
        end)
    end)
  end

  defp same_identities?(left, right),
    do: MapSet.equal?(MapSet.new(left), MapSet.new(right))
end
