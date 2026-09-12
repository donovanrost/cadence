defmodule Cadence.Applications.ReleaseRegistry do
  @moduledoc "Generic core registry for application-owned frontend release contributions."

  alias Cadence.Applications.{
    Comms,
    DerivedTelemetry,
    LegacyCommsOverview,
    Limits,
    MissionCatalog,
    OpsConsole,
    ReleaseContribution,
    Spacecraft,
    TelemetryDecomCatalogContribution
  }

  @max_contributions 128
  @contributors [
    Comms,
    LegacyCommsOverview,
    Limits,
    MissionCatalog,
    Spacecraft,
    TelemetryDecomCatalogContribution,
    OpsConsole,
    DerivedTelemetry
  ]
  @additional_contributors [Cadence.Applications.OrganizationAdmin]

  @spec all() :: [ReleaseContribution.t()]
  def all, do: all(contributors())

  @doc false
  @spec all([module()]) :: [ReleaseContribution.t()]
  def all(contributors) when is_list(contributors) do
    case collect(contributors) do
      {:ok, contributions} ->
        if valid_contributions?(contributions), do: contributions, else: []

      {:error, _reason} ->
        []
    end
  end

  def all(_contributors), do: []

  @spec validate() :: :ok | {:error, :invalid_release_contribution_registry}
  def validate, do: validate(contributors())

  @doc false
  @spec validate([module()]) :: :ok | {:error, :invalid_release_contribution_registry}
  def validate(contributors) when is_list(contributors) do
    case collect(contributors) do
      {:ok, contributions} ->
        if valid_contributions?(contributions),
          do: :ok,
          else: {:error, :invalid_release_contribution_registry}

      {:error, _reason} ->
        {:error, :invalid_release_contribution_registry}
    end
  end

  def validate(_contributors), do: {:error, :invalid_release_contribution_registry}

  defp contributors do
    @contributors ++ @additional_contributors
  end

  @spec fetch(binary(), pos_integer(), binary(), pos_integer()) ::
          {:ok, ReleaseContribution.t()} | {:error, :unknown_release_contribution}
  def fetch(application_key, application_version, surface_id, surface_version)
      when is_binary(application_key) and is_integer(application_version) and
             is_binary(surface_id) and is_integer(surface_version) do
    case Enum.find(all(), fn contribution ->
           ReleaseContribution.key(contribution) ==
             {application_key, application_version, surface_id, surface_version}
         end) do
      %ReleaseContribution{} = contribution -> {:ok, contribution}
      nil -> {:error, :unknown_release_contribution}
    end
  end

  def fetch(_application_key, _application_version, _surface_id, _surface_version),
    do: {:error, :unknown_release_contribution}

  defp collect(contributors)
       when is_list(contributors) and length(contributors) <= @max_contributions do
    contributors
    |> Enum.reduce_while({:ok, []}, &collect_contributor/2)
    |> case do
      {:ok, contributions} -> {:ok, Enum.reverse(contributions)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect(_contributors), do: {:error, :invalid_release_contribution_registry}

  defp collect_contributor(contributor, {:ok, acc}) do
    with true <- is_atom(contributor),
         true <- Code.ensure_loaded?(contributor),
         true <- function_exported?(contributor, :release_contributions, 0),
         {:ok, contributions} <- safe_apply(contributor, :release_contributions, []),
         true <- is_list(contributions),
         true <- length(contributions) <= @max_contributions,
         true <- length(acc) + length(contributions) <= @max_contributions do
      {:cont, {:ok, Enum.reverse(contributions, acc)}}
    else
      _invalid -> {:halt, {:error, :invalid_release_contribution_registry}}
    end
  end

  defp valid_contributions?(contributions)
       when is_list(contributions) and contributions != [] and
              length(contributions) <= @max_contributions do
    if Enum.all?(contributions, &(ReleaseContribution.validate(&1) == :ok)) do
      keys = Enum.map(contributions, &ReleaseContribution.key/1)
      length(keys) == length(Enum.uniq(keys))
    else
      false
    end
  end

  defp valid_contributions?(_contributions), do: false

  defp safe_apply(module, function, arguments) do
    {:ok, apply(module, function, arguments)}
  rescue
    _exception -> {:error, :contributor_exception}
  catch
    _kind, _value -> {:error, :contributor_exception}
  end
end
