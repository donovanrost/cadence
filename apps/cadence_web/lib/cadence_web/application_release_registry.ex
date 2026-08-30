defmodule CadenceWeb.ApplicationReleaseRegistry do
  @moduledoc """
  Authoritative first-party frontend release coordinates.

  A release is deployment data, so it deliberately lives outside of
  `Cadence.Applications.SurfaceDefinition`. The lookup key binds an
  application version and surface version to one immutable frontend release.
  """

  @type federation :: :module_federation | :native_federation

  @type release :: %{
          federation: federation(),
          release_id: binary(),
          remote_name: binary(),
          manifest_path: binary(),
          exposed_module: binary()
        }

  @type key :: {binary(), pos_integer(), binary(), pos_integer()}

  @releases %{
    {"comms_overview", 1, "overview", 1} => %{
      federation: :module_federation,
      release_id: "comms-overview-v1",
      remote_name: "cadence_comms_overview",
      manifest_path: "/assets/application-host/comms-overview/mf-manifest.json",
      exposed_module: "./Application"
    },
    {"telemetry_decom", 1, "packet_bindings", 1} => %{
      federation: :module_federation,
      release_id: "telemetry-decom-v1",
      remote_name: "cadence_telemetry_decom",
      manifest_path: "/assets/application-host/telemetry-decom/mf-manifest.json",
      exposed_module: "./Application"
    }
  }

  @spec all() :: [{key(), release()}]
  def all, do: Map.to_list(@releases)

  @spec fetch(binary(), pos_integer(), binary(), pos_integer()) ::
          {:ok, release()} | {:error, :unknown_application_release}
  def fetch(application_key, application_version, surface_id, surface_version)
      when is_binary(application_key) and is_integer(application_version) and
             is_binary(surface_id) and is_integer(surface_version) do
    case Map.fetch(@releases, {application_key, application_version, surface_id, surface_version}) do
      {:ok, release} -> {:ok, release}
      :error -> {:error, :unknown_application_release}
    end
  end

  def fetch(_application_key, _application_version, _surface_id, _surface_version),
    do: {:error, :unknown_application_release}
end
