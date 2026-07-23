defmodule CadenceWeb.CommsProviderNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Management.Providers

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts
  }

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    bindings = granted_bindings(scope.organization_id, mission.mission_id)
    default_grant_id = bindings |> List.first() |> binding_value(:grant_id, "")
    params = default_params(default_grant_id)

    {:ok,
     socket
     |> assign(:page_title, "New Mission Provider")
     |> assign(:nav_item, :comms_providers)
     |> assign(:provider_bindings, bindings)
     |> assign(:provider_binding_options, binding_options(bindings))
     |> assign(:grants_empty?, bindings == [])
     |> assign(:selected_binding, find_binding(bindings, default_grant_id))
     |> assign(:selected_policy_mode, params["policy_mode"])
     |> assign(:form, to_form(params, as: :provider))}
  end

  @impl true
  def handle_event("validate", %{"provider" => params}, socket) do
    {:noreply,
     socket
     |> assign(
       :selected_binding,
       find_binding(socket.assigns.provider_bindings, params["provider_account_grant_id"])
     )
     |> assign(:selected_policy_mode, params["policy_mode"])
     |> assign(:form, to_form(params, as: :provider))}
  end

  @impl true
  def handle_event("save", %{"provider" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, binding} <- selected_binding(socket.assigns.provider_bindings, params),
         {:ok, attrs} <- provider_attrs(params, mission.mission_id, binding),
         provider <- MissionProvider.new(attrs),
         {:ok, provider} <- Providers.persist_provider(scope, provider) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
       )}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  rescue
    error in ArgumentError ->
      {:noreply, put_flash(socket, :error, error.message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-provider-new-page" class="max-w-3xl space-y-6">
      <.page_header
        title="New Mission Provider"
        subtitle="Bind an organization-approved ground network account and define this mission's delivery tolerances."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Providers", ~p"/missions/#{@current_mission.mission_id}/comms/providers"},
          {"New", nil}
        ]}
      />

      <div
        :if={@grants_empty?}
        id="mission-provider-no-grants"
        class="border border-warning/40 bg-warning/10 p-5"
      >
        <p class="font-semibold">This mission has no Provider Account grants.</p>
        <p class="mt-1 text-sm text-base-content/70">
          An organization administrator must grant an account before mission setup can continue.
        </p>
        <.button class="mt-4" navigate={~p"/provider-accounts"} variant={:secondary}>
          Open Provider Accounts
        </.button>
      </div>

      <.form
        :if={!@grants_empty?}
        for={@form}
        id="mission-provider-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <.form_section number="01" title="Mission Binding">
          <.input field={@form[:display_name]} type="text" label="Display Name" required />
          <.input
            field={@form[:provider_account_grant_id]}
            type="select"
            label="Granted Provider Account"
            options={@provider_binding_options}
            required
          />

          <div :if={@selected_binding} id="mission-provider-account-summary" class="border border-base-300 bg-base-200/60 p-4">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="hud-label">Organization-owned configuration</p>
                <p class="mt-1 font-medium">{@selected_binding.account.display_name}</p>
                <p class="mt-1 font-mono text-xs text-base-content/50">
                  account v{@selected_binding.account_version.version} · grant v{@selected_binding.grant.version}
                </p>
              </div>
              <.status_badge status={:ready} label="Granted" />
            </div>
            <div class="mt-4 grid gap-3 sm:grid-cols-2">
              <div>
                <p class="hud-label">Account Guardrails</p>
                <p class="mt-1 text-xs text-base-content/70">
                  {restriction_summary(@selected_binding.account_version.guardrails)}
                </p>
              </div>
              <div>
                <p class="hud-label">Mission Restrictions</p>
                <p class="mt-1 text-xs text-base-content/70">
                  {restriction_summary(@selected_binding.grant.restrictions)}
                </p>
              </div>
            </div>
          </div>
        </.form_section>

        <.form_section number="02" title="Mission Resource Scope">
          <.input
            field={@form[:permitted_resource_refs]}
            type="text"
            label="Permitted Stations or Service Pools"
            placeholder="station-alpha, station-beta"
          />
          <p id="mission-provider-resource-guardrail-note" class="text-xs text-base-content/60">
            Leave blank to inherit the grant. Any listed resources must be inside both the account
            guardrails and the mission grant.
          </p>
        </.form_section>

        <.form_section number="03" title="Delivery Change Policy">
          <.input
            field={@form[:policy_mode]}
            type="select"
            label="Material Change Handling"
            options={[
              {"Require approval for every material change", "approval_required"},
              {"Automatically accept changes within limits", "bounded_automatic"}
            ]}
            required
          />

          <div
            :if={@selected_policy_mode == "approval_required"}
            id="mission-provider-approval-policy-guidance"
            class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70"
          >
            Provider facts are still recorded immediately, but actionable schedule or resource
            changes wait for an authorized operator decision.
          </div>

          <div
            :if={@selected_policy_mode == "bounded_automatic"}
            id="mission-provider-bounded-policy-fields"
            class="grid gap-4 sm:grid-cols-2"
          >
            <.input
              field={@form[:maximum_earlier_start_shift_seconds]}
              type="number"
              min="0"
              label="Max Earlier Start Shift (seconds)"
            />
            <.input
              field={@form[:maximum_later_start_shift_seconds]}
              type="number"
              min="0"
              label="Max Later Start Shift (seconds)"
            />
            <.input
              field={@form[:maximum_earlier_end_shift_seconds]}
              type="number"
              min="0"
              label="Max Earlier End Shift (seconds)"
            />
            <.input
              field={@form[:maximum_later_end_shift_seconds]}
              type="number"
              min="0"
              label="Max Later End Shift (seconds)"
            />
            <.input
              field={@form[:minimum_retained_duration_seconds]}
              type="number"
              min="1"
              label="Minimum Retained Duration (seconds)"
            />
            <.input
              field={@form[:approved_station_substitutions]}
              type="text"
              label="Approved Station Substitutions"
              placeholder="station-alpha, station-beta"
            />
          </div>

          <.input
            field={@form[:deadline_behavior]}
            type="select"
            label="No-response Deadline Behavior"
            options={[
              {"Retain last accepted schedule", "retain_last_accepted"},
              {"Cancel if still actionable", "cancel_if_actionable"}
            ]}
            required
          />
        </.form_section>

        <.form_actions
          submit="Create Mission Provider"
          cancel_navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers"}
        />
      </.form>
    </div>
    """
  end

  defp granted_bindings(organization_id, mission_id) do
    organization_id
    |> ProviderAccountGrants.list_for_mission(mission_id)
    |> Enum.flat_map(&granted_binding(organization_id, &1))
  end

  defp granted_binding(organization_id, grant) do
    with {:ok, account, _active_version} <-
           ProviderAccounts.fetch_for_system(organization_id, grant.provider_account_id),
         {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             organization_id,
             grant.provider_account_id,
             grant.provider_account_version
           ) do
      [
        %{
          grant_id: grant.provider_account_grant_id,
          grant: grant,
          account: account,
          account_version: account_version
        }
      ]
    else
      {:error, _reason} -> []
    end
  end

  defp default_params(grant_id) do
    %{
      "display_name" => "Ground Network Simulator",
      "provider_account_grant_id" => grant_id,
      "permitted_resource_refs" => "",
      "policy_mode" => "approval_required",
      "maximum_earlier_start_shift_seconds" => "0",
      "maximum_later_start_shift_seconds" => "0",
      "maximum_earlier_end_shift_seconds" => "0",
      "maximum_later_end_shift_seconds" => "0",
      "minimum_retained_duration_seconds" => "",
      "approved_station_substitutions" => "",
      "deadline_behavior" => "retain_last_accepted"
    }
  end

  defp selected_binding(bindings, params) do
    case find_binding(bindings, params["provider_account_grant_id"]) do
      nil -> {:error, "Select a Provider Account granted to this mission."}
      binding -> {:ok, binding}
    end
  end

  defp find_binding(bindings, grant_id), do: Enum.find(bindings, &(&1.grant_id == grant_id))

  defp provider_attrs(params, mission_id, binding) do
    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         permitted_resources = comma_list(params["permitted_resource_refs"]),
         :ok <- validate_resources(permitted_resources, binding),
         {:ok, delivery_policy} <- delivery_policy(params) do
      version = binding.account_version
      grant = binding.grant

      {:ok,
       %{
         mission_id: mission_id,
         display_name: display_name,
         provider_account_id: version.provider_account_id,
         provider_account_version: version.version,
         provider_account_grant_id: grant.provider_account_grant_id,
         provider_account_grant_version: grant.version,
         provider_type: version.provider_type,
         client_key: version.client_key,
         base_url: version.base_url,
         credential_ref: version.credential_ref,
         environment_ref: version.environment_ref,
         permitted_resource_refs: permitted_resources,
         delivery_policy_document: delivery_policy
       }}
    end
  end

  defp delivery_policy(%{"policy_mode" => "approval_required"} = params) do
    {:ok,
     %{
       "mode" => "approval_required",
       "changes_always_requiring_approval" => ["schedule", "resource", "capacity", "cost"],
       "deadline_behavior" => params["deadline_behavior"]
     }}
  end

  defp delivery_policy(%{"policy_mode" => "bounded_automatic"} = params) do
    fields = [
      "maximum_earlier_start_shift_seconds",
      "maximum_later_start_shift_seconds",
      "maximum_earlier_end_shift_seconds",
      "maximum_later_end_shift_seconds",
      "minimum_retained_duration_seconds"
    ]

    with {:ok, values} <- parse_policy_numbers(params, fields) do
      {:ok,
       values
       |> Map.put("mode", "bounded_automatic")
       |> Map.put("deadline_behavior", params["deadline_behavior"])
       |> Map.put(
         "approved_station_substitutions",
         comma_list(params["approved_station_substitutions"])
       )}
    end
  end

  defp delivery_policy(_params), do: {:error, "Select a delivery change policy."}

  defp parse_policy_numbers(params, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, values} ->
      case optional_nonnegative_integer(params[field]) do
        {:ok, nil} -> {:cont, {:ok, values}}
        {:ok, value} -> {:cont, {:ok, Map.put(values, field, value)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp validate_resources([], _binding), do: :ok

  defp validate_resources(resources, binding) do
    allowed =
      Map.get(binding.grant.restrictions, "allowed_stations") ||
        Map.get(binding.account_version.guardrails, "allowed_stations")

    if is_nil(allowed) or MapSet.subset?(MapSet.new(resources), MapSet.new(allowed)) do
      :ok
    else
      {:error, "Permitted resources must stay within the Provider Account grant."}
    end
  end

  defp binding_options(bindings) do
    Enum.map(bindings, fn binding ->
      {"#{binding.account.display_name} · account v#{binding.account_version.version} · grant v#{binding.grant.version}",
       binding.grant_id}
    end)
  end

  defp binding_value(nil, _key, default), do: default
  defp binding_value(binding, key, _default), do: Map.fetch!(binding, key)

  defp restriction_summary(restrictions) when map_size(restrictions) == 0,
    do: "No additional limits"

  defp restriction_summary(restrictions) do
    Enum.map_join(restrictions, " · ", fn {key, value} ->
      "#{humanize(key)}: #{restriction_value(value)}"
    end)
  end

  defp restriction_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp restriction_value(value), do: to_string(value)

  defp required_text(value, message) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, message}
      trimmed -> {:ok, trimmed}
    end
  end

  defp required_text(_value, message), do: {:error, message}

  defp comma_list(value) when is_binary(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp comma_list(_value), do: []

  defp optional_nonnegative_integer(value) when value in [nil, ""], do: {:ok, nil}

  defp optional_nonnegative_integer(value) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number >= 0 -> {:ok, number}
      _other -> {:error, "Delivery policy limits must be non-negative whole numbers."}
    end
  end

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_error(%Ecto.Changeset{} = changeset),
    do: CadenceWeb.CommsComponents.format_error(changeset)

  defp format_error(reason), do: "Could not create provider: #{inspect(reason)}"
end
