defmodule Cadence.Contacts.PathTemplateStore.ArchivedProfile do
  @moduledoc """
  A path template pinned to a provider profile version whose profile was since deleted (its
  transport was archived, lead 11-16, ae6ae335a) doesn't resolve. When that version was
  materialized from a transport, the refusal names it, from the version's own metadata, so a
  pass that can't start says why: `{:contact_provider_profile_archived, %{provider_profile_id,
  transport_id, transport_name}}` (the `contact_start` reason `transport_archived`, ux U45). Any
  other case keeps `:contact_provider_profile_not_found`. HTTP answers both the same (404).
  """

  @doc """
  `:ok` while the pinned `profile` version's latest is live (`latest` is that fetch's result), else
  the refusal.
  """
  @spec live({:ok, term()} | {:error, term()}, map()) :: :ok | {:error, term()}
  def live({:ok, _latest}, _profile), do: :ok
  def live({:error, :contact_provider_profile_not_found}, profile), do: {:error, refusal(profile)}
  def live({:error, reason}, _profile), do: {:error, reason}

  defp refusal(
         %{metadata: %{"materialized_from_transport_id" => transport_id} = metadata} = profile
       )
       when is_binary(transport_id) do
    {:contact_provider_profile_archived,
     %{
       provider_profile_id: profile.provider_profile_id,
       transport_id: transport_id,
       transport_name: Map.get(metadata, "display_name")
     }}
  end

  defp refusal(_profile), do: :contact_provider_profile_not_found
end
