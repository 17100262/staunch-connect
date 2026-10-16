class ConnectionsController < ApplicationController
  AUTH_ERRORS = [ ClickupClient::AuthenticationError, HubstaffClient::AuthenticationError, FathomClient::AuthenticationError, AnthropicConnection::AuthenticationError ].freeze
  REQUEST_ERRORS = [ ClickupClient::RequestError, HubstaffClient::RequestError, FathomClient::RequestError, AnthropicConnection::RequestError ].freeze

  # Connectors live in the settings modal now; this keeps the old URL (and the
  # redirects after connect, sync and disconnect) working.
  def index
    flash.keep
    redirect_to settings_path(section: "connectors")
  end

  def create
    source = params[:source]

    unless Connection::SOURCES.include?(source)
      return redirect_to connections_path, alert: "Unknown source."
    end

    if params[:credential].blank?
      return redirect_to connections_path, alert: "Enter a credential."
    end

    connection = Connection.find_or_initialize_by(source: source)
    connection.credential = params[:credential]
    connection.access_token = nil
    connection.access_token_expires_at = nil

    begin
      client = client_for(connection, use_cached_access_token: false)
      client.verify!
      persist_client_tokens(connection, client)
      webhook_error = source == "fathom" ? register_fathom_webhook(connection, client) : nil
      connection.status = :connected
      connection.last_error = nil
      connection.last_used_at = Time.current
      connection.save!

      notice = "#{source.capitalize} connected."
      notice += " Webhook registration failed (#{webhook_error}) — meetings will only sync via \"Sync Now\" until this is fixed." if webhook_error
      redirect_to connections_path, notice: notice
    rescue *AUTH_ERRORS => e
      mark_error(connection, e.message)
    rescue *REQUEST_ERRORS => e
      mark_error(connection, e.message)
    end
  end

  def sync
    connection = Connection.find(params[:id])
    @return_to = local_path(params[:return_to])

    if connection.source == "fathom"
      connection.update!(status: :syncing)
      FathomSyncJob.perform_later(connection.id)
      return redirect_to after_sync_path, notice: "Fathom sync started in the background — meetings will appear as they're pulled in."
    end

    begin
      client = client_for(connection)
      client.verify!
      persist_client_tokens(connection, client)
      connection.update!(status: :connected, last_error: nil, last_used_at: Time.current)
      redirect_to after_sync_path, notice: (connection.source == "anthropic" ? "Anthropic key works." : "#{connection.source.capitalize} synced.")
    rescue *AUTH_ERRORS => e
      mark_error(connection, e.message)
    rescue *REQUEST_ERRORS => e
      mark_error(connection, e.message)
    end
  end

  def destroy
    connection = Connection.find(params[:id])
    source = connection.source
    deregister_fathom_webhook(connection) if source == "fathom"
    connection.destroy
    redirect_to connections_path, notice: "#{source.capitalize} disconnected."
  end

  private

  # Sync can be started from the settings modal or from a page like Meetings;
  # go back to wherever it was started.
  def after_sync_path
    @return_to || connections_path
  end

  def local_path(path)
    path.to_s.start_with?("/") && !path.to_s.start_with?("//") ? path.to_s : nil
  end

  def client_for(connection, use_cached_access_token: true)
    case connection.source
    when "hubstaff"
      if use_cached_access_token
        HubstaffClient.new(connection.credential, access_token: connection.access_token, access_token_expires_at: connection.access_token_expires_at)
      else
        HubstaffClient.new(connection.credential)
      end
    when "clickup"
      ClickupClient.new(connection.credential)
    when "fathom"
      FathomClient.new(connection.credential)
    when "anthropic"
      AnthropicConnection.new(connection.credential)
    end
  end

  # Registers this app's webhook endpoint with Fathom so new meetings sync in
  # near-real-time (FATHOM_INTEGRATION_SPEC.md Section 5.2) — re-registering on
  # reconnect replaces any previous registration rather than accumulating one
  # per connect, since Fathom only ever needs to know about the current secret.
  #
  # Deliberately non-fatal: a valid API key should still connect even if
  # webhook registration fails (e.g. Fathom requires an HTTPS destination_url,
  # which a local dev server without a tunnel can't offer) — the manual
  # "Sync Now" backstop (Section 5.1/3) covers exactly this case. Returns the
  # error message on failure (surfaced in the flash notice), nil on success.
  def register_fathom_webhook(connection, client)
    webhook = client.create_webhook("#{request.base_url}#{webhooks_fathom_path}")
    connection.webhook_id = webhook[:id]
    connection.webhook_secret = webhook[:secret]
    nil
  rescue FathomClient::AuthenticationError, FathomClient::RequestError => e
    e.message
  end

  # Best-effort — a Fathom-side failure here shouldn't block disconnecting in
  # this app; an orphaned webhook registration is a minor cleanup issue, not a
  # reason to leave a connection the user asked to remove.
  def deregister_fathom_webhook(connection)
    return if connection.webhook_id.blank?

    FathomClient.new(connection.credential).delete_webhook(connection.webhook_id)
  rescue FathomClient::AuthenticationError, FathomClient::RequestError
    nil
  end

  # Hubstaff's token exchange rotates the refresh token on every call, so the
  # previous one stops working — the new value must always be saved back.
  def persist_client_tokens(connection, client)
    return unless client.is_a?(HubstaffClient)

    connection.credential = client.refresh_token
    connection.access_token = client.access_token
    connection.access_token_expires_at = client.access_token_expires_at
  end

  def mark_error(connection, message)
    connection.status = :error
    connection.last_error = message
    connection.save!
    redirect_to (@return_to || connections_path), alert: message
  end
end
