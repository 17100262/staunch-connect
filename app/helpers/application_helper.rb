module ApplicationHelper
  # Renders a Fathom meeting summary's markdown (headers, bold, bullet lists,
  # and links to timestamped moments in the recording) as real HTML. Redcarpet
  # is told to strip any raw HTML embedded in the source (`filter_html`); the
  # output is sanitized again afterward as defense-in-depth, since this text
  # ultimately reflects whatever was said in a meeting, not just Fathom's own
  # formatting.
  MARKDOWN_RENDERER = Redcarpet::Markdown.new(
    Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, link_attributes: { target: "_blank", rel: "noopener" }),
    autolink: true, no_intra_emphasis: true
  )

  def markdown_to_html(text)
    return "" if text.blank?

    sanitize(
      MARKDOWN_RENDERER.render(text),
      tags: %w[h1 h2 h3 h4 p ul ol li strong em a br blockquote code],
      attributes: %w[href target rel]
    )
  end

  ASSISTANT_MARKDOWN = Redcarpet::Markdown.new(
    Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, link_attributes: { target: "_blank", rel: "noopener" }),
    autolink: true, no_intra_emphasis: true, tables: true, fenced_code_blocks: true, strikethrough: true
  )

  # Renders an assistant answer (markdown from the model) as sanitized HTML, with
  # tables, lists and code styled by the SC components.
  def assistant_html(text)
    return "".html_safe if text.blank?

    html = sanitize(
      ASSISTANT_MARKDOWN.render(text),
      tags: %w[h1 h2 h3 h4 p ul ol li strong em del a br blockquote code pre table thead tbody tr th td],
      attributes: %w[href target rel]
    )
    fragment = Nokogiri::HTML.fragment(html)
    fragment.css("h1, h2, h3, h4").each { |node| node["class"] = "t-heading-sm" }
    fragment.css("ul, ol").each { |node| node["class"] = "msg-list"; node["style"] = "list-style:#{node.name == 'ol' ? 'decimal' : 'disc'}" }
    fragment.css("pre").each { |node| node["class"] = "msg-code" }
    fragment.css("table").each do |table|
      table["class"] = "table"
      table["data-density"] = "compact"
      table.css("td:not(:first-child), th:not(:first-child)").each do |cell|
        cell["class"] = "num" if cell.text.strip.match?(/\A[\p{Sc}\d.,%+\-−\s hH]+\z/)
      end
      table.replace(%(<div class="table-card" data-variant="open"><div class="table-scroll" tabindex="0" role="region" aria-label="Table">#{table.to_html}</div></div>))
    end
    fragment.to_html.html_safe
  end

  # Inline SVG icon from the SC sprite (layouts render shared/_icons once).
  def icon(name, **attrs)
    css = [ "icon", attrs.delete(:class) ].compact.join(" ")
    tag.svg(tag.use(href: "#i-#{name}"), class: css, aria: { hidden: true }, **attrs)
  end

  # Flash messages as SC alerts.
  def flash_alerts
    tones = { "alert" => [ "danger", "circle-alert" ] }
    safe_join(flash.filter_map do |type, message|
      tone, icon_name = tones[type.to_s]
      next unless tone

      tag.div(class: "alert", role: "alert", data: { tone: tone }, id: type.to_s) do
        icon(icon_name) + tag.div(message, class: "alert-content")
      end
    end)
  end

  def attendee_names(meeting)
    Array(meeting.attendees).map { |a| a.is_a?(Hash) ? (a["name"].presence || a["email"]) : a }.compact
  end

  # Groups chats for the list: Today, then one group per month.
  def chat_groups(conversations)
    conversations.group_by { |c| c.updated_at.to_date == Date.current ? "Today" : c.updated_at.strftime("%B %Y") }
  end

  ASSISTANT_SOURCE_NAMES = { "fathom" => "Fathom", "clickup" => "ClickUp", "hubstaff" => "Hubstaff" }.freeze

  # Names of the connected sources the assistant can read from.
  def assistant_source_names
    Connection.where(status: %w[connected syncing]).pluck(:source).filter_map { |source| ASSISTANT_SOURCE_NAMES[source] }
  end

  def assistant_sub(names = assistant_source_names)
    names.any? ? "Uses #{source_summary(names)}" : "Needs at least one connected source"
  end

  def source_summary(names)
    names.size > 1 ? "#{names[0..-2].join(', ')} and #{names.last}" : names.first.to_s
  end

  AVATAR_TONES = %w[brand info success warning].freeze

  def person_initials(name)
    name.to_s.split(/[\s@.]+/).reject(&:blank?).first(2).map { |part| part[0] }.join.upcase.presence || "?"
  end

  # A person keeps one tone, picked from their name; inside one group no two avatars share a tone.
  def person_tone(name, taken = [])
    index = Zlib.crc32(name.to_s) % AVATAR_TONES.size
    AVATAR_TONES.size.times do
      tone = AVATAR_TONES[index]
      return tone unless taken.include?(tone)

      index = (index + 1) % AVATAR_TONES.size
    end
    AVATAR_TONES[index]
  end

  # Up to three avatars: every person when there are three or fewer, otherwise two people and "+N".
  def attendee_stack(names)
    shown = names.size <= 3 ? names : names.first(2)
    taken = []
    stack = shown.map do |name|
      tone = person_tone(name, taken)
      taken << tone
      { text: person_initials(name), tone: tone }
    end
    stack << { text: "+#{names.size - 2}", tone: nil } if names.size > 3
    stack
  end
end
