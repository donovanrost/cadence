defmodule Cadence.Applications.ReleaseRegistry do
  @moduledoc "Generic core registry for application-owned frontend release contributions."

  alias Cadence.Applications.{
    LegacyCommsOverview,
    ReleaseContribution,
    TelemetryDecomCatalogContribution
  }

  @contributors [LegacyCommsOverview, TelemetryDecomCatalogContribution]

  @spec all() :: [ReleaseContribution.t()]
  def all do
    Enum.flat_map(@contributors, fn contributor -> contributor.release_contributions() end)
  end

  @spec validate() :: :ok | {:error, :invalid_release_contribution_registry}
  def validate do
    contributions = all()
    keys = Enum.map(contributions, &ReleaseContribution.key/1)

    if contributions != [] and
         Enum.all?(contributions, &(ReleaseContribution.validate(&1) == :ok)) and
         length(keys) == length(Enum.uniq(keys)),
       do: :ok,
       else: {:error, :invalid_release_contribution_registry}
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
end
