defmodule Cadence.Accounts.UserNotifier do
  @moduledoc """
  Handles email notifications for user account operations.

  This module sends emails for:
  - Magic link login
  - Account confirmation
  - Email change instructions
  - Notification digests
  """

  import Swoosh.Email

  alias Cadence.Accounts.User
  alias Cadence.Mailer
  alias Cadence.Notifications.Notification
  alias Cadence.Repo

  # Get base URL from application config instead of CadenceWeb.Endpoint
  # This removes the web layer dependency from the domain layer
  defp base_url do
    Application.get_env(:cadence, :base_url, "http://localhost:4000")
  end

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Cadence", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  # ============================================================================
  # Notification Emails
  # ============================================================================

  @doc """
  Delivers a notification email immediately.
  """
  def deliver_notification(%Notification{} = notification) do
    notification = Repo.preload(notification, :user)
    user = notification.user

    subject = notification_subject(notification)
    body = notification_email_body(notification)

    deliver(user.email, subject, body)
  end

  @doc """
  Delivers a digest email with multiple notifications.
  """
  def deliver_notification_digest(user, notifications, period) do
    period_text =
      case period do
        :daily -> "Daily"
        :weekly -> "Weekly"
      end

    subject = "#{period_text} Notification Digest - Cadence"
    body = build_digest_body(notifications, period_text)

    deliver(user.email, subject, body)
  end

  defp notification_subject(%Notification{type: type, metadata: metadata}) do
    procedure_name = metadata["procedure_name"] || metadata[:procedure_name] || "Procedure"

    case type do
      "procedure_submitted" ->
        "[Cadence] New procedure awaiting review: #{procedure_name}"

      "procedure_approved" ->
        "[Cadence] Your procedure was approved: #{procedure_name}"

      "procedure_rejected" ->
        "[Cadence] Your procedure was rejected: #{procedure_name}"

      "procedure_finalized" ->
        "[Cadence] Procedure finalized: #{procedure_name}"

      _ ->
        "[Cadence] Notification"
    end
  end

  defp notification_email_body(notification) do
    """

    ==============================

    #{notification.title}

    #{notification.body}

    View in Cadence: #{base_url()}#{notification.action_url}

    ==============================
    """
  end

  defp build_digest_body(notifications, period_text) do
    notification_list = Enum.map_join(notifications, "\n", fn n -> "- #{n.title}" end)

    """

    ==============================

    #{period_text} Notification Summary

    You have #{length(notifications)} new notification(s):

    #{notification_list}

    View all in Cadence: #{base_url()}/notifications

    ==============================
    """
  end
end
