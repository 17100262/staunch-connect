RSpec.describe "Invoicing" do
  let(:tasks) do
    [
      clickup_task(id: "t1", name: "Build homepage", hours: 10, custom_id: "ACM-1"),
      clickup_task(id: "t2", name: "Fix login", hours: 2),
      clickup_task(id: "t3", name: "Write copy", parent: "t1")
    ]
  end

  before { sign_in_via_ui(create(:user)) }

  it "asks you to connect ClickUp and Hubstaff first" do
    visit invoices_path
    first(:link, "Create invoice").click

    expect(page).to have_text("Invoicing needs both ClickUp and Hubstaff connected")
  end

  context "with ClickUp and Hubstaff connected" do
    before do
      create(:connection, :clickup)
      create(:connection, :hubstaff)
      stub_hubstaff_token_refresh
      stub_clickup_workspace
      stub_clickup_tasks("list_1", tasks)
      stub_hubstaff_organizations
      stub_hubstaff_projects
      stub_hubstaff_daily_activities(tracked_seconds: [ 3600 * 13 ])
    end

    def open_setup
      visit invoices_path
      expect(page).to have_text("No invoices yet")
      first(:link, "Create invoice").click
      expect(page).to have_css("#ni-t", text: "Which project?")
    end

    def pick_project_and_list
      open_setup
      find("label", text: "Acme Website").click
      click_on "Continue"
      expect(page).to have_css("#ni-t", text: "Which lists?")
      find("label", text: "Sprint 1").click
      expect(page).to have_text("1 selected")
      click_on "Continue"
      expect(page).to have_css("#ni-t", text: "Check the setup")
    end

    it "builds, reviews and saves an invoice" do
      pick_project_and_list

      within("[role=dialog]") do
        expect(page).to have_text("Staunch / Acme Website")
        expect(page).to have_css(".badge", text: "Matched")
        click_on "Change the rate"
        find("[aria-label='Hourly rate for this invoice']").fill_in(with: "150")
        expect(page).to have_text("$150.00")
        click_on "Build invoice"
      end

      expect(page).to have_css("h1", text: "Review")
      expect(page).to have_text("Acme Website")
      within("[aria-label=Reconciliation]") do
        expect(page).to have_text("Build homepage")
        expect(page).to have_text("Fix login")
        expect(page).to have_text("$1,800.00") # 12h × $150
      end
      expect(page).to have_text("13.0 h") # Hubstaff logged
      expect(page).to have_text("8% over")

      click_on "Save as invoice"

      expect(page).to have_text("Invoice saved.")
      invoice = Invoice.sole
      expect(page).to have_current_path(invoice_path(invoice))
      expect(invoice.invoice_line_items.pluck(:hourly_rate).uniq).to eq([ 150 ])
    end

    it "filters projects and only enables Continue after a choice" do
      open_setup

      expect(page).to have_button("Continue", disabled: true)
      find("[aria-label='Search projects']").fill_in(with: "zzz")
      expect(page).to have_text("No project matches")
      find("[aria-label='Search projects']").fill_in(with: "web")
      find("label", text: "Acme Website").click

      expect(page).to have_button("Continue", disabled: false)
    end

    it "rejects a rate that isn't a number" do
      pick_project_and_list

      click_on "Change the rate"
      find("[aria-label='Hourly rate for this invoice']").fill_in(with: "12abc")

      expect(page).to have_text("Use numbers only, like 40 or 42.50.")
      expect(page).to have_button("Build invoice", disabled: true)
    end

    it "can skip the Hubstaff comparison" do
      pick_project_and_list

      click_on "Change the Hubstaff project"
      within("[aria-labelledby=hub-t]") do
        find("label", text: "Do not compare").click
        click_on "Use this project"
      end
      expect(page).to have_css("[data-setup-target=hubBadge]", text: "Not compared")
      click_on "Build invoice"

      expect(page).to have_text("Not compared with Hubstaff")
      expect(a_request(:get, /activities/)).not_to have_been_made
    end

    it "keeps the setup open when Esc closes the Hubstaff picker",
       pending: "analysis.md #18: Esc in the Hubstaff sub-dialog also closes the whole setup modal" do
      pick_project_and_list

      click_on "Change the Hubstaff project"
      find("[aria-label='Search Hubstaff projects']").send_keys(:escape)

      expect(page).to have_css("#ni-t", text: "Check the setup")
    end

    it "goes back a step and closes with Esc" do
      pick_project_and_list

      click_on "Back"
      expect(page).to have_css("#ni-t", text: "Which lists?")

      find("body").send_keys(:escape)
      expect(page).to have_no_css("#ni-t")
    end

    it "shows subtasks on the review page" do
      pick_project_and_list
      click_on "Build invoice"

      expect(page).to have_no_text("Write copy")
      click_on "1 subtask"
      expect(page).to have_text("Write copy")
    end

    it "changes the billing period from the review page" do
      pick_project_and_list
      click_on "Build invoice"

      previous = 1.month.ago.beginning_of_month
      find("#rv-m").select(previous.strftime("%B %Y"))

      expect(page).to have_current_path(/month=#{previous.strftime('%Y-%m')}/)
      expect(page).to have_text(previous.strftime("%B %Y"))
    end
  end

  describe "a saved invoice" do
    let!(:invoice) { create(:invoice, :with_line_items, name: "Acme Website", month: "2026-09") }

    it "edits estimates and rates with live totals, then saves" do
      visit invoice_path(invoice)
      expect(page).to have_css("[data-invoice-editor-target=badge]", text: "Saved")
      expect(page).to have_button("Save changes", disabled: true)

      fill_in "Estimate in hours for Fix login", with: "5"

      within(".total-bar") { expect(page).to have_text("$1,500.00") }
      expect(page).to have_css("[data-invoice-editor-target=badge]", text: "Unsaved changes")

      fill_in "Rate per hour for Fix login", with: "abc"
      expect(page).to have_text("Some hours or rates have letters or symbols in them.")
      expect(page).to have_button("Save changes", disabled: true)

      fill_in "Rate per hour for Fix login", with: "120"
      within(".total-bar") { expect(page).to have_text("$1,600.00") }
      click_on "Save changes"

      expect(page).to have_text("Changes saved.")
      expect(invoice.invoice_line_items.find_by(title: "Fix login")).to have_attributes(estimate_hours: 5, hourly_rate: 120)
    end

    it "leaves a task off the bill" do
      visit invoice_path(invoice)

      find("label.check", text: "", match: :first) # wait for the table
      find("[aria-label='Bill Build homepage']", visible: :all).find(:xpath, "..").click

      within(".total-bar") { expect(page).to have_text("$250.00") }
      click_on "Save changes"

      expect(page).to have_text("Changes saved.")
      expect(invoice.invoice_line_items.find_by(title: "Build homepage")).not_to be_billable
    end

    it "renames the invoice" do
      visit invoice_path(invoice)

      click_on "Rename invoice"
      fill_in "Invoice name", with: "Acme Website — September\n"
      expect(page).to have_css("h1", text: "Acme Website — September")
      click_on "Save changes"

      expect(page).to have_text("Changes saved.")
      expect(invoice.reload.name).to eq("Acme Website — September")
    end

    it "exports an XLSX" do
      visit invoice_path(invoice)

      click_on "Export XLSX"
      within("[aria-labelledby=ex-t]") do
        fill_in "File name", with: "acme-sept"
        click_on "Export XLSX"
      end

      expect { Dir[DOWNLOADS_PATH.join("*.xlsx")].first }.to eventually_exist
      expect(File.basename(Dir[DOWNLOADS_PATH.join("*.xlsx")].first)).to eq("acme-sept.xlsx")
    end

    it "deletes from the invoice page after confirming" do
      visit invoice_path(invoice)

      click_on "Delete invoice"
      within("[aria-labelledby=dl-t]") { click_on "Delete invoice" }

      expect(page).to have_text("Invoice deleted.")
      expect(page).to have_text("No invoices yet")
    end

    it "deletes from the list after confirming, and cancel keeps it" do
      visit invoices_path

      click_on "Delete Acme Website"
      within("[aria-labelledby=dv-t-#{invoice.id}]") { click_on "Cancel" }
      expect(page).to have_no_css("[aria-labelledby=dv-t-#{invoice.id}]", visible: true)

      click_on "Delete Acme Website"
      within("[aria-labelledby=dv-t-#{invoice.id}]") { click_on "Delete invoice" }

      expect(page).to have_text("No invoices yet")
      expect(Invoice.count).to eq(0)
    end
  end
end
