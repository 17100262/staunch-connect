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

  # Inline SVG icon from the SC sprite (layouts render shared/_icons once).
  def icon(name, **attrs)
    css = [ "icon", attrs.delete(:class) ].compact.join(" ")
    tag.svg(tag.use(href: "#i-#{name}"), class: css, aria: { hidden: true }, **attrs)
  end

  # Flash messages as SC alerts.
  def flash_alerts
    tones = { "notice" => [ "success", "circle-check" ], "alert" => [ "danger", "circle-alert" ] }
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
end
