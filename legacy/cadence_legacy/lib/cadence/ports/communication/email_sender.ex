defmodule Cadence.Ports.Communication.EmailSender do
  @moduledoc """
  Port (behavior) defining the contract for sending emails.

  This behavior abstracts email delivery from the domain, enabling:
  - Unit testing without actually sending emails
  - Swapping email providers (Swoosh, SendGrid, SES, etc.)
  - Clear separation between business logic and infrastructure

  ## Implementations

  - `Cadence.Adapters.Messaging.SwooshEmailSender` - Production via Swoosh
  - `Cadence.Test.Adapters.FakeEmailSender` - Collects emails for test assertions
  """

  @type email :: %{
          required(:to) => String.t() | [String.t()],
          required(:subject) => String.t(),
          required(:body) => String.t(),
          optional(:html_body) => String.t(),
          optional(:from) => {String.t(), String.t()},
          optional(:reply_to) => String.t(),
          optional(:cc) => [String.t()],
          optional(:bcc) => [String.t()],
          optional(:attachments) => [attachment()]
        }

  @type attachment :: %{
          filename: String.t(),
          content: binary(),
          content_type: String.t()
        }

  @type delivery_result :: {:ok, metadata :: map()} | {:error, reason :: term()}

  @doc """
  Sends an email synchronously.

  Returns `{:ok, metadata}` on success, where metadata contains delivery details
  (message ID, etc.), or `{:error, reason}` on failure.

  ## Example

      EmailSender.send_email(%{
        to: "user@example.com",
        subject: "Password Reset",
        body: "Click here to reset your password: https://...",
        from: {"Cadence", "noreply@cadence.space"}
      })
  """
  @callback send_email(email()) :: delivery_result()

  @doc """
  Sends an email asynchronously (fire and forget).

  Returns `:ok` immediately. Delivery errors are logged but not returned.
  Use this for non-critical emails where delivery confirmation isn't needed.
  """
  @callback send_email_async(email()) :: :ok

  @doc """
  Sends a batch of emails.

  Returns a list of results corresponding to each email in the input list.
  Useful for bulk notifications.
  """
  @callback send_batch([email()]) :: [delivery_result()]

  @doc """
  Returns the configured email sender implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(:cadence, :email_sender, Cadence.Adapters.Messaging.SwooshEmailSender)
  end
end
