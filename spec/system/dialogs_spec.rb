RSpec.describe "Dialogs" do
  let!(:invoice) { create(:invoice, :with_line_items, name: "Acme Website") }

  before { sign_in_via_ui(create(:user)) }

  def dialog_open?(labelledby)
    page.has_css?("[aria-labelledby=#{labelledby}]", visible: true, wait: 1)
  end

  it "closes with Escape and returns focus to the button that opened it" do
    visit invoice_path(invoice)

    click_on "Delete invoice"
    expect(dialog_open?("dl-t")).to be(true)

    find("body").send_keys(:escape)
    expect(page).to have_no_css("[aria-labelledby=dl-t]", visible: true)
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("Delete invoice")
  end

  it "closes when clicking the backdrop" do
    visit invoices_path

    click_on "Delete Acme Website"
    scrim = find("[aria-labelledby=dv-t-#{invoice.id}]").ancestor(".scrim")
    page.execute_script("arguments[0].click()", scrim) # a click on the backdrop itself, outside the dialog

    expect(page).to have_no_css("[aria-labelledby=dv-t-#{invoice.id}]", visible: true)
    expect(Invoice.exists?(invoice.id)).to be(true)
  end

  it "moves focus into the dialog when it opens" do
    visit invoice_path(invoice)

    click_on "Export XLSX"

    expect(page.evaluate_script("!!document.activeElement.closest('[aria-labelledby=ex-t]')")).to be(true)
  end

  it "keeps keyboard focus inside an open dialog", pending: "analysis.md #18: dialogs don't trap focus" do
    visit invoice_path(invoice)
    click_on "Delete invoice"

    6.times { page.driver.browser.keyboard.type(:tab) }

    inside = page.evaluate_script("!!document.activeElement.closest('[aria-labelledby=dl-t]')")
    expect(inside).to be(true)
  end
end
