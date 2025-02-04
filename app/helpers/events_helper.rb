module EventsHelper
  def event_day_title(day)
    case
    when day.today?
      "Today"
    when day.yesterday?
      "Yesterday"
    else
      day.strftime("%A, %B %e")
    end
  end

  def event_column(event)
    case event.action
    when "popped"
      4
    when "published"
      3
    when "commented"
      2
    else
      1
    end
  end

  def event_cluster_tag(hour, col, &)
    row = 25 - hour
    tag.div class: "event__wrapper", style: "grid-area: #{row}/#{col}", &
  end

  def event_next_page_link(next_day)
    if next_day
      tag.div id: "next_page",
        data: { controller: "fetch-on-visible", fetch_on_visible_url_value: events_path(day: next_day.strftime("%Y-%m-%d")) }
    end
  end

  def render_event_grid_cells(day, columns: 4, rows: 24)
    safe_join((2..rows + 1).map do |row|
      (1..columns).map do |col|
        tag.div class: class_names("event__grid-item"), style: "grid-area: #{row}/#{col};"
      end
    end.flatten)
  end

  def render_column_headers
    [ "Touched", "Discussed", "Added", "Popped" ].map do |header|
      content_tag(:h3, header, class: "event__grid-column-title margin-block-end-half position-sticky")
    end.join.html_safe
  end

  def event_action_sentence(event)
    case event.action
    when "assigned"
      "Assigned to #{ event.assignees.pluck(:name).to_sentence }"
    when "unassigned"
      "Unassigned #{ event.assignees.pluck(:name).to_sentence }"
    when "boosted"
      "Boosted by #{ event.creator.name }"
    when "commented"
      "#{ strip_tags(event.comment.body_html).blank? ? "#{ event.creator.name } replied." : "#{ event.creator.name }:" } #{ strip_tags(event.comment.body_html).truncate(200) }"
    when "published"
      "Added by #{ event.creator.name }"
    when "popped"
      "Popped by #{ event.creator.name }"
    when "staged"
      "#{event.creator.name} moved to #{event.stage_name}."
    end
    # FIXME: Should track dates(added/changed) and perhaps "renamed"
  end

  def event_action_icon(event)
    case event.action
    when "assigned"
      "arrow-right"
    when "boosted"
      "thumb-up"
    when "staged"
      "bolt"
    when "unassigned"
      "remove-med"
    else
      "check"
    end
  end
end
