class MeetingsController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @meetings = Meeting.search(@query).order(recorded_at: :desc)
  end

  def show
    @meeting = Meeting.find(params[:id])
  end
end
