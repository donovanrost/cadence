defmodule Cadence.Administration.ServiceIdentityIssuance do
  @moduledoc "Finite platform administration issuance; the plaintext token is returned only with the effect."
  alias Cadence.Administration.Access
  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.{Ids, Organizations}

  def issue(scope, organization_id, input) do
    with {:ok, _user} <- Access.authorize(scope),
         true <- Ids.valid_identifier?(organization_id),
         {:ok, _organization} <- Organizations.fetch_organization(organization_id),
         {:ok, attrs} <- validate(input),
         identity <-
           ServiceIdentity.new(
             Map.merge(attrs, %{
               organization_id: organization_id,
               capabilities: [:organization_admin],
               lifecycle_state: :active,
               metadata: %{}
             })
           ) do
      case Auth.issue_service_identity(identity) do
        {:ok, %{service_identity: saved, api_token: token}} ->
          {:ok,
           %{
             "id" => saved.service_identity_id,
             "name" => saved.display_name,
             "api_token" => token
           }}

        {:error, %Ecto.Changeset{errors: errors}} ->
          issuance_error(errors)

        _ ->
          {:error, :unavailable}
      end
    else
      {:invalid, _} = invalid -> invalid
      _ -> {:error, :unavailable}
    end
  end

  defp validate(%{"display_name" => name, "service_identity_id" => id} = input)
       when map_size(input) == 2 and is_binary(name) and is_binary(id) do
    name = String.trim(name)
    id = String.trim(id)

    cond do
      byte_size(name) not in 1..200 or String.match?(name, ~r/[\x00-\x1f\x7f]/u) ->
        {:invalid, %{"display_name" => "Enter a display name of up to 200 bytes."}}

      id != "" and not Ids.valid_identifier?(id) ->
        {:invalid,
         %{
           "service_identity_id" =>
             "Use a valid identity of up to 120 characters, or leave this blank."
         }}

      id == "" ->
        {:ok, %{display_name: name}}

      true ->
        {:ok, %{display_name: name, service_identity_id: id}}
    end
  end

  defp validate(_), do: {:invalid, %{"form" => "Enter a display name and optional identity."}}

  defp issuance_error(errors) do
    if Keyword.has_key?(errors, :service_identity_id),
      do: {:invalid, %{"service_identity_id" => "This identity is already in use."}},
      else: {:error, :unavailable}
  end
end
