class Event < ActiveRecord::Base
  has_many :reservations
  has_many :notes, dependent: :destroy
  belongs_to :space
  belongs_to :event_type
  belongs_to :recurring_event

  # validate :is_available, :is_postive_time, :room_capactity
  validates :space_id, :start_date, :end_date, :title, :event_style, presence: true

  scope :unapproved, -> { where(approved: [nil, false]) }
  scope :same_space, -> (space_id){ where('space_id = ?', space_id)}
  scope :diff_event, -> (event_id){ where('id != ?', event_id)}
  scope :overlaping, -> (start, endd){
    return [] if endd - start > 1.day
    where('(? < end_date AND ? > start_date)', start, endd)
  }
  scope :by_date, -> (day){ where(start_date: day.beginning_of_day..day.end_of_day)}

  include IceCube
  attr_accessor :recurring_rules

  def repeat days
    days = self.end_date - self.start_date
    current_day = self.start_date
    days.each do |d|
      current_day += 1
    end
  end
  def as_json(options = { })
      h = super(options)
      h[:color]   =  self.event_type && self.event_type.color || "#000"
      h
  end
  def is_available
    start = self.start_date
    endd = self.end_date
    if self.id
      @events = Event.same_space(self.space_id).diff_event(self.id).overlaping(start, endd)
    else
      @events = Event.same_space(self.space_id).overlaping(start, endd)
    end
    if @events.count > 0
      errors.add(:event, "space and time are not available during the date/time you requested.<br>These events conflict: " + @events.map{|e|  "https://gadc.space/events/" + e.id.to_s }.join("<br>"))
    end
  end
  def is_postive_time
    if (self.start_date > self.end_date) || (self.start_date == self.end_date)
      errors.add(:event, "time is not valid, the start must come before the end.")
    end
  end
  def room_capactity
    @space = Space.find(self.space_id)
    cap = @space.classroom_cap || @space.lecture_cap
    if self.event_style == 'Lecture'
      if cap && self.number_of_attendees && self.number_of_attendees > cap
        errors.add(:event, "space selected has a max lecture capacity of #{@space.lecture_cap}, please select a different space." )
      end
    else
      if cap && self.number_of_attendees && self.number_of_attendees > cap
        errors.add(:event, "space selected has a max classroom capacity of #{@space.classroom_cap}, please select a different space." )
      end
    end
  end
  # TODO validation for recurring events sucks
  # TODO can't update non-recurring event to become recurring
  def color
    if self.custom_color
      self.custom_color
    elsif self.event_type
      self.event_type.color
    end
  end
  def self.recurring_helper(params, event_params, start_date, end_date)
    rec_rules  = RecurringSelect.dirty_hash_to_rule(params['event']['recurring_rules'])
    dur_in_sec = end_date.seconds_since_midnight - start_date.seconds_since_midnight
    total_dur = (end_date.strftime("%s").to_i - start_date.strftime("%s").to_i)
    sched = Schedule.new(start_date, :duration => total_dur)
    sched.add_recurrence_rule(rec_rules)
    occurrences = sched.occurrences_between(start_date, end_date + 1.day)
    occurrences = occurrences.map{|o| o.to_datetime.change(:offset => "+0000")}
    return [dur_in_sec, sched, occurrences]
  end
  def self.update_recurring_events(params, event_params, start_date, end_date, recurring_event)
    new_st = start_date
    new_et = end_date
    if start_date.strftime('%D') == end_date.strftime('%D')
      old_st = recurring_event.start_date.to_datetime
      old_et = recurring_event.end_date.to_datetime
      start_date = DateTime.new(old_st.year, old_st.month, old_st.day, new_st.hour, new_st.minute, new_st.second)
      end_date = DateTime.new(old_et.year, old_et.month, old_et.day, new_et.hour, new_et.minute, new_et.second)
    end
    dur_in_sec, sched, occurrences = self.recurring_helper(params, event_params, start_date, end_date)
    recurring_event.update!(event_params.merge(start_date: start_date, end_date: end_date, recurring_rules: sched.to_hash))
    occurrences.each do |occurrence|
      recurring_event.events.create!(event_params.merge(start_date: occurrence, end_date: occurrence + dur_in_sec.seconds))
    end
  end
  def self.create_recurring_events(params, event_params, start_date, end_date)
    dur_in_sec, sched, occurrences = self.recurring_helper(params, event_params, start_date, end_date)
    rec = RecurringEvent.create!(event_params.merge(start_date: start_date, end_date: end_date, recurring_rules: sched.to_hash))
  end
end
