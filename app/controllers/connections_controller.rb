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

    begin
      client_for(source, params[:credential]).verify!
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
      client_for(connection.source, connection.credential).verify!
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

  def client_for(source, token)
    case source
    when "hubstaff" then HubstaffClient.new(token)
    when "clickup" then ClickupClient.new(token)
    end
  end

  def mark_error(connection, message)
    connection.status = :error
    connection.last_error = message
    connection.save!
    redirect_to connections_path, alert: message
  end
end
