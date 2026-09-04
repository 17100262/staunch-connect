class ConnectionsController < ApplicationController
  def index
    @connections = Connection::SOURCES.index_with { |source| Connection.find_by(source: source) }
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
      connection.status = :connected
      connection.last_error = nil
      connection.last_used_at = Time.current
      connection.save!
      redirect_to connections_path, notice: "#{source.capitalize} connected."
    rescue ClickupClient::AuthenticationError, HubstaffClient::AuthenticationError => e
      mark_error(connection, e.message)
    rescue ClickupClient::RequestError, HubstaffClient::RequestError => e
      mark_error(connection, e.message)
    end
  end

  def sync
    connection = Connection.find(params[:id])

    begin
      client = client_for(connection)
      client.verify!
      persist_client_tokens(connection, client)
      connection.update!(status: :connected, last_error: nil, last_used_at: Time.current)
      redirect_to connections_path, notice: "#{connection.source.capitalize} synced."
    rescue ClickupClient::AuthenticationError, HubstaffClient::AuthenticationError => e
      mark_error(connection, e.message)
    rescue ClickupClient::RequestError, HubstaffClient::RequestError => e
      mark_error(connection, e.message)
    end
  end

  def destroy
    connection = Connection.find(params[:id])
    source = connection.source
    connection.destroy
    redirect_to connections_path, notice: "#{source.capitalize} disconnected."
  end

  private

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
    end
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
    redirect_to connections_path, alert: message
  end
end
