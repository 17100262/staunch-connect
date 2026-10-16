class MeetingsController < ApplicationController
  PER_PAGE = 25
  RANGES = { "7" => 7.days, "30" => 30.days }.freeze

  def index
    @query = params[:q].to_s.strip
    @range = RANGES.key?(params[:range].to_s) ? params[:range].to_s : "all"
    @only_actions = params[:ai] == "1"
    @selected_people = Array(params[:attendees]).reject(&:blank?)

    scope = Meeting.search(@query)
    scope = scope.recorded_since(RANGES[@range].ago) if @range != "all"
    scope = scope.with_open_action_items if @only_actions
    scope = scope.with_attendees(@selected_people) if @selected_people.any?

    @filtered = @query.present? || @range != "all" || @only_actions || @selected_people.any?
    @total = scope.count
    @page = [ params[:page].to_i, 1 ].max
    @pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = @pages if @page > @pages
    @meetings = scope.order(recorded_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    @fathom = Connection.find_by(source: "fathom")
    @has_meetings = @filtered || Meeting.exists?
    @people = people_options
  end

  def show
    @meeting = Meeting.find(params[:id])
  end

  private

  # The most frequent attendees across all meetings, for the attendee filter.
  def people_options
    counts = Hash.new(0)
    Meeting.pluck(:attendees).each do |list|
      Array(list).each do |a|
        next unless a.is_a?(Hash)

        key = a["email"].presence || a["name"].presence
        counts[[ key, a["name"].presence || key ]] += 1 if key
      end
    end
    counts.sort_by { |_, n| -n }.first(25).map { |(value, label), _| { value: value, label: label } }
  end
end
