module ApplicationHelper
  def sidebar_link(label, path, icon:, active: false)
    classes = [ "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors" ]
    classes << (active ? "bg-brand-50 text-brand-400 font-semibold" : "text-slate-600 font-medium hover:bg-slate-100")

    link_to path, class: classes.join(" ") do
      safe_join([
        tag.i(class: "#{active ? "ph-fill" : "ph"} ph-#{icon} text-lg"),
        tag.span(label, class: "flex-1")
      ])
    end
  end

  def sidebar_soon(label, icon:)
    content_tag :div, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm text-slate-400 font-medium cursor-not-allowed" do
      safe_join([
        tag.i(class: "ph ph-#{icon} text-lg"),
        tag.span(label, class: "flex-1"),
        tag.span("Soon", class: "text-[11px] font-semibold px-2 py-0.5 rounded-full bg-slate-100 text-slate-500")
      ])
    end
  end

  def sidebar_section(label)
    tag.div(label, class: "px-3 pt-3.5 pb-1.5 text-[11px] font-semibold tracking-wider uppercase text-slate-400")
  end
end
