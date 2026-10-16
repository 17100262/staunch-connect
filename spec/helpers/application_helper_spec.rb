RSpec.describe ApplicationHelper do
  describe "#markdown_to_html" do
    it "renders markdown" do
      html = helper.markdown_to_html("## Title\n\n**bold** [link](https://fathom.video/x)")

      expect(html).to include("<h2>Title</h2>", "<strong>bold</strong>")
      expect(html).to include('href="https://fathom.video/x"', 'target="_blank"')
    end

    it "strips raw HTML and scripts from meeting content" do
      html = helper.markdown_to_html("hi <script>alert(1)</script><img src=x onerror=alert(1)>")

      expect(html).not_to include("<script", "onerror", "<img")
    end

    it "drops javascript: links" do
      expect(helper.markdown_to_html("[click](javascript:alert(1))")).not_to include("javascript:")
    end

    it "returns an empty string for blank text" do
      expect(helper.markdown_to_html(nil)).to eq("")
    end
  end

  describe "#assistant_html" do
    it "styles tables and marks numeric cells" do
      html = helper.assistant_html("| Project | Total |\n|---|---|\n| Acme | $1,250.00 |")

      expect(html).to include('class="table-card"', 'class="table"')
      expect(html).to match(/<td class="num">\$1,250\.00<\/td>/)
    end

    it "styles lists and code blocks" do
      html = helper.assistant_html("- one\n- two\n\n```\ncode\n```")

      expect(html).to include('class="msg-list"', 'class="msg-code"')
    end

    it "removes scripts" do
      expect(helper.assistant_html("<script>alert(1)</script>ok")).not_to include("<script")
    end
  end

  it "#icon renders a sprite reference" do
    html = helper.icon("check", class: "big")

    expect(html).to include('class="icon big"', 'aria-hidden="true"', 'href="#i-check"')
  end

  it "#flash_alerts only renders alerts" do
    flash[:alert] = "Broken"
    flash[:notice] = "Saved"

    html = helper.flash_alerts

    expect(html).to include("Broken", 'data-tone="danger"')
    expect(html).not_to include("Saved")
  end

  it "#attendee_names prefers names over emails" do
    meeting = build(:meeting, attendees: [ { "name" => "Ada" }, { "email" => "g@x.co" } ])

    expect(helper.attendee_names(meeting)).to eq([ "Ada", "g@x.co" ])
  end

  it "#chat_groups puts today's chats under Today and older ones by month" do
    travel_to Time.zone.local(2026, 10, 16, 12) do
      today = build(:ai_conversation, updated_at: Time.current)
      older = build(:ai_conversation, updated_at: Time.zone.local(2026, 8, 3))

      expect(helper.chat_groups([ today, older ])).to eq("Today" => [ today ], "August 2026" => [ older ])
    end
  end

  it "#assistant_source_names lists connected data sources only" do
    create(:connection, :fathom)
    create(:connection, :clickup, :errored)
    create(:connection, :anthropic)

    expect(helper.assistant_source_names).to eq([ "Fathom" ])
  end

  describe "#assistant_sub" do
    it "asks for an Anthropic key first" do
      with_env("ANTHROPIC_API_KEY" => nil) do
        allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return(nil)

        expect(helper.assistant_sub([ "Fathom" ])).to eq("Needs an Anthropic API key")
      end
    end

    it "summarises the connected sources" do
      create(:connection, :anthropic)

      expect(helper.assistant_sub([ "Fathom", "ClickUp", "Hubstaff" ])).to eq("Uses Fathom, ClickUp and Hubstaff")
      expect(helper.assistant_sub([])).to eq("Needs at least one connected source")
    end
  end

  it "#person_initials handles names and emails" do
    expect(helper.person_initials("Ada Lovelace")).to eq("AL")
    expect(helper.person_initials("grace@client.com")).to eq("GC")
    expect(helper.person_initials("")).to eq("?")
  end

  it "#attendee_stack gives distinct tones and collapses extra people into +N" do
    stack = helper.attendee_stack([ "Ada", "Grace", "Alan", "Linus" ])

    expect(stack.map { |s| s[:text] }).to eq([ "A", "G", "+2" ])
    expect(stack.first(2).map { |s| s[:tone] }.uniq.size).to eq(2)
  end
end
