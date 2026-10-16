# Settings always open in the modal (Profile, Password, Notifications, Connectors).
# A direct visit shows the Home page with the modal opened over it.
class SettingsController < ApplicationController
  SECTIONS = %w[profile password notifications connectors].freeze

  before_action :set_user

  def show
    @section = SECTIONS.include?(params[:section]) ? params[:section] : "profile"

    unless turbo_frame_request?
      @modal_src = request.fullpath
      return render "home/index"
    end

    @connections = Connection::SOURCES.index_with { |source| Connection.find_by(source: source) } if @section == "connectors"
  end

  def update_profile
    if @user.update(params.require(:user).permit(:name, :email_address, :job_title, :time_zone))
      redirect_to settings_path(section: "profile"), notice: "Profile saved."
    else
      redirect_to settings_path(section: "profile"), alert: @user.errors.full_messages.to_sentence
    end
  end

  def update_password
    if !@user.authenticate(params[:current_password].to_s)
      redirect_to settings_path(section: "password"), alert: "Your current password isn't right."
    elsif params[:password] != params[:password_confirmation]
      redirect_to settings_path(section: "password"), alert: "The new passwords don't match."
    elsif (problems = User.password_problems(params[:password])).any?
      redirect_to settings_path(section: "password"), alert: "Your new password needs: #{problems.map(&:downcase).to_sentence}."
    else
      @user.update!(password: params[:password], password_confirmation: params[:password_confirmation])
      redirect_to settings_path(section: "password"), notice: "Password updated."
    end
  end

  private

  def set_user
    @user = Current.user
  end
end
