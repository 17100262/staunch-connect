RSpec.describe "Invoices" do
  let(:frame) { { "Turbo-Frame" => "modal" } }
  let(:setup) do
    { clickup_space_id: "space_1", clickup_space_name: "Acme", clickup_folder_id: "folder_1",
      clickup_folder_name: "Acme Website", list_ids: [ "list_1" ], month: "2026-09", rate: "120",
      hubstaff_project_value: "501|Staunch / Acme Website" }
  end
  let(:tasks) do
    [
      clickup_task(id: "t1", name: "Build homepage", hours: 10, custom_id: "ACM-1",
                   custom_fields: [ { "name" => "HTN", "value" => "HTN-42" } ]),
      clickup_task(id: "t2", name: "Fix login", hours: 2.5),
      clickup_task(id: "t3", name: "Write copy", parent: "t1"),
      clickup_task(id: "t4", name: "Unestimated")
    ]
  end

  before { sign_in_as(create(:user)) }

  context "without ClickUp and Hubstaff connected" do
    it "explains what to connect" do
      create(:connection, :clickup)

      get invoicing_path

      expect(response.body).to include("Connect Hubstaff and ClickUp first", "Hubstaff isn")
      expect(response.body).not_to include("ClickUp isn")
    end

    it "shows an error inside the setup modal" do
      get invoicing_path, headers: frame

      expect(response.body).to include("Invoicing needs both ClickUp and Hubstaff connected")
    end
  end

  context "with both connected" do
    let!(:hubstaff) { create(:connection, :hubstaff, credential: "hs-rt") }

    before do
      create(:connection, :clickup)
      stub_clickup_workspace
      stub_hubstaff_token_refresh(rotated_to: "hs-rotated")
    end

    it "lists saved invoices" do
      create(:invoice, :with_line_items, name: "Acme Website", month: "2026-09")

      get invoices_path

      expect(response.body).to include("Acme Website")
    end

    it "opens the setup modal over the list on a direct visit" do
      get invoicing_path

      expect(response.body).to include("Invoicing", invoicing_path)
    end

    describe "setup steps" do
      it "step 1 lists the workspace's projects" do
        get invoicing_path(step: 1), headers: frame

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Website")
      end

      it "step 2 lists the folder's lists" do
        get invoicing_path(step: 2, clickup_space_id: "space_1", clickup_folder_id: "folder_1"), headers: frame

        expect(response.body).to include("Sprint 1", "Sprint 2")
      end

      it "step 3 matches a Hubstaff project by name" do
        stub_hubstaff_organizations
        stub_hubstaff_projects

        get invoicing_path(setup.merge(step: 3, hubstaff_project_value: nil)), headers: frame

        expect(response.body).to include("Staunch / Acme Website", "Matched by name")
      end

      it "falls back to step 1 when no project was chosen" do
        get invoicing_path(step: 3), headers: frame

        expect(response.body).to include("Acme Website")
        expect(response.body).not_to include("Compare with a Hubstaff project")
      end

      it "shows ClickUp errors inside the modal" do
        stub_clickup("/team", {}, status: 401)

        get invoicing_path(step: 1), headers: frame

        expect(response.body).to include("ClickUp rejected this token.")
      end
    end

    describe "draft" do
      before do
        stub_clickup_tasks("list_1", tasks)
        stub_hubstaff_organizations
        stub_hubstaff_daily_activities(tracked_seconds: [ 3600 * 9, 1800 ])
      end

      it "reconciles ClickUp estimates against Hubstaff hours" do
        get invoicing_draft_path(setup)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("HTN-42 - Build homepage", "Fix login", "Write copy")
        expect(assigns_like(:total_estimate_hours)).to eq(12.5)
      end

      it "saves Hubstaff's rotated token" do
        get invoicing_draft_path(setup)

        expect(hubstaff.reload.credential).to eq("hs-rotated")
      end

      it "skips Hubstaff when comparison is off" do
        get invoicing_draft_path(setup.merge(hubstaff_project_value: "none"))

        expect(a_request(:get, /activities/)).not_to have_been_made
      end

      it "sends you back without a project or lists" do
        get invoicing_draft_path(setup.merge(list_ids: []))

        expect(response).to redirect_to(invoices_path)
        expect(flash[:alert]).to eq("Choose a project and at least one list first.")
      end
    end

    describe "create" do
      before { stub_clickup_tasks("list_1", tasks) }

      it "builds the invoice from ClickUp tasks" do
        expect { post invoices_path, params: setup }.to change(Invoice, :count).by(1)

        invoice = Invoice.last
        expect(response).to redirect_to(invoice_path(invoice))
        expect(invoice).to have_attributes(name: "Acme Website", month: "2026-09")
        expect(invoice.project_mapping).to have_attributes(clickup_folder_id: "folder_1", hubstaff_project_id: "501", default_hourly_rate: 120)

        homepage = invoice.invoice_line_items.find_by(clickup_task_id: "t1")
        expect(homepage).to have_attributes(title: "HTN-42 - Build homepage", ticket: "ACM-1", estimate_hours: 10, hourly_rate: 120, notes: "• Write copy")
        expect(invoice.invoice_line_items.find_by(clickup_task_id: "t2").ticket).to eq("t2")
        expect(invoice.invoice_line_items.find_by(clickup_task_id: "t4").estimate_hours).to eq(0)
        expect(invoice.invoice_line_items.where(clickup_task_id: "t3")).to be_empty
      end

      it "opens the existing invoice for a month already billed" do
        mapping = create(:project_mapping, clickup_folder_id: "folder_1")
        existing = create(:invoice, project_mapping: mapping, month: "2026-09")

        expect { post invoices_path, params: setup }.not_to change(Invoice, :count)
        expect(response).to redirect_to(invoice_path(existing))
        expect(flash[:notice]).to match(/September 2026 already exists/)
      end

      it "reuses one mapping per space for folderless lists" do
        post invoices_path, params: setup.merge(clickup_folder_id: "none", clickup_folder_name: "")

        expect(ProjectMapping.last).to have_attributes(clickup_folder_id: nil, clickup_space_id: "space_1")
        expect(Invoice.last.name).to eq("Acme")
      end

      it "reports ClickUp failures" do
        stub_clickup("/list/list_1/task", {}, status: 500, query: { "page" => "0" })

        post invoices_path, params: setup

        expect(response).to redirect_to(invoices_path)
        expect(flash[:alert]).to match(/ClickUp request failed \(500\)/)
      end

      it "does not change an existing mapping when the month is already billed",
         pending: "analysis.md #8: mapping.save! runs before the duplicate check" do
        mapping = create(:project_mapping, clickup_folder_id: "folder_1", hubstaff_project_id: "old")
        create(:invoice, project_mapping: mapping, month: "2026-09")

        post invoices_path, params: setup

        expect(mapping.reload.hubstaff_project_id).to eq("old")
      end
    end
  end

  describe "a saved invoice" do
    let(:invoice) { create(:invoice, :with_line_items, month: "2026-09") }

    it "shows its line items" do
      get invoice_path(invoice)

      expect(response.body).to include("Build homepage", "Fix login", "Internal sync")
    end

    it "saves edits to the name and line items" do
      item = invoice.invoice_line_items.find_by(title: "Fix login")

      patch invoice_path(invoice), params: { invoice: { name: "Renamed", invoice_line_items_attributes: [ { id: item.id, estimate_hours: "4", hourly_rate: "90", billable: "0" } ] } }

      expect(response).to redirect_to(invoice_path(invoice))
      expect(invoice.reload.name).to eq("Renamed")
      expect(item.reload).to have_attributes(estimate_hours: 4, hourly_rate: 90, billable: false)
    end

    it "can't edit another invoice's line items" do
      other_item = create(:invoice_line_item, title: "Not yours")

      patch invoice_path(invoice), params: { invoice: { invoice_line_items_attributes: [ { id: other_item.id, title: "Hijacked" } ] } }

      expect(response).to have_http_status(:not_found)
      expect(other_item.reload.title).to eq("Not yours")
    end

    it "re-renders with an error for a blank name", pending: "analysis.md #8: update! raises instead of re-rendering" do
      patch invoice_path(invoice), params: { invoice: { name: "" } }

      # Today update! raises and the user gets Rails' generic 422 error page instead of the form.
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Build homepage", "can&#39;t be blank")
    end

    it "deletes" do
      delete invoice_path(invoice)

      expect(response).to redirect_to(invoices_path)
      expect(Invoice.exists?(invoice.id)).to be(false)
      expect(InvoiceLineItem.where(invoice_id: invoice.id)).to be_empty
    end

    describe "export" do
      def rows
        Tempfile.create([ "invoice", ".xlsx" ], binmode: true) do |file|
          file.write(response.body)
          file.flush
          sheet = Roo::Excelx.new(file.path).sheet(0)
          (1..sheet.last_row).map { |i| sheet.row(i) }
        end
      end

      it "downloads billable lines with subtask notes and a total" do
        get export_invoice_path(invoice)

        expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        expect(response.headers["Content-Disposition"]).to include("invoice-acme-website-2026-09.xlsx")
        expect(rows.first).to eq([ "Task", "Ticket", "Hours", "Rate", "Amount", "Notes" ])
        expect(rows.map(&:first)).to include("Build homepage", "Fix login")
        expect(rows.map(&:first)).not_to include("Internal sync")
        expect(rows.last.compact).to eq([ "Total", 1250 ])
      end

      it "can include non-billable lines and drop notes" do
        get export_invoice_path(invoice, include_off: "1", include_subtasks: "0")

        expect(rows.first).to eq([ "Task", "Ticket", "Hours", "Rate", "Amount", "Billed" ])
        expect(rows.find { |r| r.first == "Internal sync" }.last).to eq("No")
      end

      it "uses a custom file name" do
        get export_invoice_path(invoice, file_name: "Acme Sept.xlsx")

        expect(response.headers["Content-Disposition"]).to include("acme-sept.xlsx")
      end
    end
  end

  # Reads an instance variable off the last request's controller.
  def assigns_like(name)
    controller.instance_variable_get(:"@#{name}")
  end
end
