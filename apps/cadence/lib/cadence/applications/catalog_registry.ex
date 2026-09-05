defmodule Cadence.Applications.CatalogRegistry do
  @moduledoc "Generic core registry for application-owned compatibility catalog contributions."

  alias Cadence.Applications.{
    ApplicationDefinition,
    CatalogContribution,
    Comms,
    JSONBoundary,
    LegacyCommsOverview,
    MissionCatalog,
    OpsConsole,
    Spacecraft,
    TelemetryDecomCatalogContribution
  }

  @max_contributions 64
  @contributors [
    Comms,
    LegacyCommsOverview,
    MissionCatalog,
    Spacecraft,
    TelemetryDecomCatalogContribution,
    OpsConsole
  ]
  @optional_contributors [CadenceWeb.ApplicationContributions.OrganizationAdmin]

  @spec validate() :: :ok | {:error, :invalid_application_catalog_registry}
  def validate do
    case collect(contributors()) do
      {:ok, contributions} ->
        if valid_contributions?(contributions),
          do: :ok,
          else: {:error, :invalid_application_catalog_registry}

      {:error, _reason} ->
        {:error, :invalid_application_catalog_registry}
    end
  end

  @spec all() :: [CatalogContribution.t()]
  def all do
    case collect(contributors()) do
      {:ok, contributions} ->
        if valid_contributions?(contributions), do: contributions, else: []

      {:error, _reason} ->
        []
    end
  end

  @spec fetch(binary()) ::
          {:ok, CatalogContribution.t()} | {:error, :unknown_catalog_contribution}
  def fetch(application_key) when is_binary(application_key) do
    case Enum.find(all(), fn %CatalogContribution{definition: definition} ->
           definition.application_key == application_key
         end) do
      %CatalogContribution{} = contribution -> {:ok, contribution}
      nil -> {:error, :unknown_catalog_contribution}
    end
  end

  def fetch(_application_key), do: {:error, :unknown_catalog_contribution}

  @spec fetch_default(ApplicationDefinition.scope()) ::
          {:ok, CatalogContribution.t()} | {:error, :unknown_catalog_contribution}
  def fetch_default(scope) when is_atom(scope) do
    case Enum.find(all(), fn %CatalogContribution{definition: definition} ->
           scope in definition.installable_scopes
         end) do
      %CatalogContribution{} = contribution -> {:ok, contribution}
      nil -> {:error, :unknown_catalog_contribution}
    end
  end

  def fetch_default(_scope), do: {:error, :unknown_catalog_contribution}

  defp contributors do
    @contributors ++ Enum.filter(@optional_contributors, &Code.ensure_loaded?/1)
  end

  defp collect(contributors), do: collect_contributors(contributors)

  defp collect_contributors(contributors)
       when is_list(contributors) and length(contributors) <= @max_contributions do
    contributors
    |> Enum.reduce_while({:ok, []}, &collect_contributor/2)
    |> normalize_contributions()
  end

  defp collect_contributors(_contributors),
    do: {:error, :invalid_application_catalog_registry}

  defp collect_contributor(contributor, {:ok, acc}) do
    with true <- is_atom(contributor),
         true <- Code.ensure_loaded?(contributor),
         true <- function_exported?(contributor, :catalog_contributions, 0),
         {:ok, contributions} <- safe_apply(contributor, :catalog_contributions, []),
         true <- is_list(contributions),
         true <- length(contributions) <= @max_contributions,
         true <- length(acc) + length(contributions) <= @max_contributions do
      {:cont, {:ok, acc ++ contributions}}
    else
      _invalid -> {:halt, {:error, :invalid_application_catalog_registry}}
    end
  end

  defp normalize_contributions({:ok, contributions}) when is_list(contributions),
    do: {:ok, contributions}

  defp normalize_contributions({:error, reason}), do: {:error, reason}

  defp valid_contributions?(contributions)
       when is_list(contributions) and length(contributions) <= @max_contributions do
    if Enum.all?(contributions, &valid_contribution?/1) do
      unique?(Enum.map(contributions, &contribution_identity/1)) and
        unique?(Enum.map(contributions, &package_identity/1))
    else
      false
    end
  end

  defp valid_contributions?(_contributions), do: false

  defp valid_contribution?(%CatalogContribution{
         definition: %ApplicationDefinition{} = definition,
         package_id: package_id,
         package_version: package_version
       }) do
    ApplicationDefinition.validate(definition) == :ok and
      valid_text?(definition.application_key) and valid_text?(package_id) and
      is_integer(package_version) and package_version > 0
  end

  defp valid_contribution?(_contribution), do: false

  defp contribution_identity(%CatalogContribution{definition: definition}),
    do: {definition.application_key, definition.version}

  defp contribution_identity(_contribution), do: nil

  defp package_identity(%CatalogContribution{package_id: package_id, package_version: version}),
    do: {package_id, version}

  defp package_identity(_contribution), do: nil

  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp valid_text?(value) when is_binary(value) and value != "" do
    JSONBoundary.validate(value) == :ok
  end

  defp valid_text?(_value), do: false

  defp safe_apply(module, function, arguments) do
    {:ok, apply(module, function, arguments)}
  rescue
    _exception -> {:error, :contributor_exception}
  catch
    _kind, _value -> {:error, :contributor_exception}
  end
end
