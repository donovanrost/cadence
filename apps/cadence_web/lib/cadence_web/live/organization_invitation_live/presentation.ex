defmodule CadenceWeb.OrganizationInvitationLive.Presentation do
  @moduledoc false

  use CadenceWeb, :html

  alias Phoenix.HTML.Form

  @doc false
  def build(assigns, error_message) when is_map(assigns) do
    invitation_available? = Map.fetch!(assigns, :invitation_available?)
    invitation = Map.get(assigns, :invitation)
    organization = Map.get(assigns, :organization)

    %{
      root:
        element(%{
          "class" => "space-y-6",
          "id" => "organization-invitation"
        }),
      header: header(invitation_available?),
      error: error(error_message),
      cards: cards(organization, invitation),
      form: acceptance_form(assigns, invitation_available?)
    }
  end

  @doc false
  def raw_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp header(true) do
    header(
      "Accept your invitation and establish durable operator access.",
      "Invitation acceptance creates or finishes the durable human account, establishes tenant membership, and then signs you into the operator shell."
    )
  end

  defp header(false) do
    header(
      "This invitation is no longer available.",
      "Invitation links are single-use handoff artifacts. Ask a Cadence platform administrator to issue a fresh invitation if you still need access."
    )
  end

  defp header(heading, body) do
    %{
      root: element(%{}),
      label: text("Cadence Invitation", %{"class" => "hud-label"}),
      heading: text(heading, %{"class" => "text-2xl font-bold text-base-content"}),
      body:
        text(body, %{
          "class" => "mt-2 text-sm text-base-content/70 max-w-2xl"
        })
    }
  end

  defp error(nil), do: nil

  defp error(message) do
    text(message, %{
      "class" => "alert alert-error",
      "id" => "organization-invitation-error"
    })
  end

  defp cards(organization, invitation) do
    %{
      root: element(%{"class" => "grid grid-cols-1 md:grid-cols-3 gap-4"}),
      items: [
        card(
          "Organization",
          if(organization, do: organization.display_name, else: "Unavailable"),
          if(organization,
            do: "Slug: #{organization.slug}",
            else: "Cadence could not resolve the invitation target from this link."
          ),
          "text-sm text-base-content/60"
        ),
        card(
          "Email",
          if(invitation, do: invitation.email, else: "Unavailable"),
          "This invitation is bound to a specific email address and establishes the durable user identity for that operator.",
          "text-sm text-base-content/70"
        ),
        card(
          "Access",
          if(invitation,
            do: Phoenix.Naming.humanize(invitation.membership_role),
            else: "Pending new invitation"
          ),
          if(invitation,
            do: "Platform Admin: #{if(invitation.grant_platform_admin, do: "Yes", else: "No")}",
            else: "The original invitation details are no longer available from this link."
          ),
          "text-sm text-base-content/60"
        )
      ]
    }
  end

  defp card(title, primary, detail, detail_class) do
    %{
      root: element(%{"class" => "card bg-base-200 border border-base-300"}),
      body: element(%{"class" => "card-body p-6"}),
      title: text(title, %{"class" => "hud-label"}),
      primary: text(primary, %{"class" => "font-semibold"}),
      detail: text(detail, %{"class" => detail_class})
    }
  end

  defp acceptance_form(_assigns, false), do: nil

  defp acceptance_form(assigns, true) do
    form = Map.fetch!(assigns, :form)
    invitation_token = Map.fetch!(assigns, :invitation_token)
    action = ~p"/invitations/#{invitation_token}"

    %{
      attrs:
        raw_attrs(%{
          "action" => action,
          "class" => "space-y-4",
          "id" => "organization-invitation-acceptance-form",
          "method" => "post"
        }),
      hidden_fields: [csrf_field(action)],
      fields: [
        field(
          "Display Name",
          %{
            "autofocus" => true,
            "id" => "organization_invitation_acceptance_display_name",
            "name" => "organization_invitation_acceptance[display_name]",
            "placeholder" => "Flight Operator",
            "required" => true,
            "type" => "text",
            "value" => Form.input_value(form, :display_name)
          }
        ),
        field(
          "Password",
          %{
            "autocomplete" => "new-password",
            "id" => "organization_invitation_acceptance_password",
            "name" => "organization_invitation_acceptance[password]",
            "placeholder" => "Create a durable account password",
            "required" => true,
            "type" => "password"
          }
        ),
        field(
          "Confirm Password",
          %{
            "autocomplete" => "new-password",
            "id" => "organization_invitation_acceptance_password_confirmation",
            "name" => "organization_invitation_acceptance[password_confirmation]",
            "placeholder" => "Re-enter your password",
            "required" => true,
            "type" => "password"
          }
        )
      ],
      actions: %{
        root:
          element(%{
            "class" => "flex items-center justify-between gap-4 flex-wrap"
          }),
        submit:
          text("Accept Invitation", %{
            "class" => "btn btn-primary",
            "type" => "submit"
          }),
        help:
          text(
            "Passwords must be at least 12 characters. Accepting this invitation signs you into the durable operator session immediately.",
            %{"class" => "text-sm text-base-content/70"}
          )
      }
    }
  end

  defp field(label, input_attrs) do
    %{
      root: element(%{"class" => "fieldset mb-3"}),
      label: text(label, %{"class" => "hud-label block mb-1.5"}),
      input: element(Map.put(input_attrs, "class", "w-full input"))
    }
  end

  defp csrf_field(action) do
    element(%{
      "hidden" => true,
      "name" => "_csrf_token",
      "type" => "hidden",
      "value" => Plug.CSRFProtection.get_csrf_token_for(action)
    })
  end

  defp element(attrs), do: %{attrs: raw_attrs(attrs)}
  defp text(value, attrs), do: %{attrs: raw_attrs(attrs), text: value}
end
