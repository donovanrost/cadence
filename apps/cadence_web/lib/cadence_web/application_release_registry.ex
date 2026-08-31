defmodule CadenceWeb.ApplicationReleaseRegistry do
  @moduledoc "Generic lookup of release metadata contributed by application owners."

  alias Cadence.Applications.{ReleaseContribution, ReleaseRegistry}

  @type federation :: :module_federation | :native_federation

  @type release :: %{
          federation: federation(),
          release_id: binary(),
          remote_name: binary(),
          manifest_path: binary(),
          exposed_module: binary()
        }

  @type key :: {binary(), pos_integer(), binary(), pos_integer()}

  @spec all() :: [{key(), release()}]
  def all do
    ReleaseRegistry.all()
    |> Enum.map(fn contribution ->
      {ReleaseContribution.key(contribution), ReleaseContribution.release(contribution)}
    end)
  end

  @spec fetch(binary(), pos_integer(), binary(), pos_integer()) ::
          {:ok, release()} | {:error, :unknown_application_release}
  def fetch(application_key, application_version, surface_id, surface_version)
      when is_binary(application_key) and is_integer(application_version) and
             is_binary(surface_id) and is_integer(surface_version) do
    case Enum.find(all(), fn {key, _release} ->
           key == {application_key, application_version, surface_id, surface_version}
         end) do
      {_key, release} -> {:ok, release}
      nil -> {:error, :unknown_application_release}
    end
  end

  def fetch(_application_key, _application_version, _surface_id, _surface_version),
    do: {:error, :unknown_application_release}
end
