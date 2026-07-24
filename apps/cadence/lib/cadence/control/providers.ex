defmodule Cadence.Control.Providers do
  @moduledoc "Control-plane boundary for external provider validation and inventory operations."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.ProviderReservations
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.ProviderAccountGrants
  alias Cadence.Management.Providers
  alias Cadence.Management.Providers.ProviderConfiguration

  @spec validate_current(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def validate_current(%Scope{} = scope, mission_id, provider_id, opts \\ []) do
    with :ok <- authorize(scope, mission_id),
         {:ok, configuration} <-
           Providers.operational_configuration(scope.organization_id, mission_id, provider_id) do
      validate(configuration, opts)
    end
  end

  @spec validate(ProviderConfiguration.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def validate(%ProviderConfiguration{} = configuration, opts \\ []) do
    GroundNetworks.validate_provider_configuration(configuration.provider, opts)
  end

  @spec sync_current(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def sync_current(%Scope{} = scope, mission_id, provider_id, opts \\ []) do
    with :ok <- authorize(scope, mission_id),
         {:ok, configuration} <-
           Providers.operational_configuration(scope.organization_id, mission_id, provider_id) do
      sync(configuration, opts)
    end
  end

  @spec sync(ProviderConfiguration.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def sync(%ProviderConfiguration{} = configuration, opts \\ []) do
    GroundNetworks.sync_provider_configuration(configuration.provider, opts)
  end

  @spec revoke_account_grant(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def revoke_account_grant(%Scope{} = scope, grant_id, reason, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, revoked} <- ProviderAccountGrants.revoke(scope, grant_id, reason, opts),
         {:ok, _affected_count} <-
           ProviderReservations.mark_provider_grant_for_review(revoked, now) do
      {:ok, revoked}
    end
  end

  defp authorize(scope, mission_id) do
    Policy.authorize(scope, :manage_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end
end
