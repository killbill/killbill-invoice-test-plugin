require 'spec_helper'
require 'logger'

describe InvoiceTest::InvoicePlugin do

  class FakeJavaInvoiceUserApi
    attr_accessor :invoices

    def get_invoices_by_account(accountId, includesMigrated, context)
      @invoices
    end
  end

  before(:each) do
    @invoice_api = FakeJavaInvoiceUserApi.new
    kb_apis      = Killbill::Plugin::KillbillApi.new('killbill-invoice-test', {:invoice_user_api => @invoice_api})

    @plugin         = InvoiceTest::InvoicePlugin.new
    @plugin.logger  = Logger.new(STDOUT)
    @plugin.kb_apis = kb_apis

    @properties   = []
    @call_context = nil
  end

  it 'should start and stop correctly' do
    @plugin.start_plugin
    @plugin.stop_plugin
  end

  it 'should add two additional items' do
    fixed_item     = build_invoice_item(100, :FIXED)
    recurring_item = build_invoice_item(150, :RECURRING)
    invoice        = build_invoice([fixed_item, recurring_item])

    new_items = @plugin.get_additional_invoice_items(invoice, false, @properties, @call_context)
    new_items.size.should == 2

    check_invoice_item(new_items[0], 7, fixed_item)
    check_invoice_item(new_items[1], 10.5, recurring_item)

    check_idempotency(invoice, new_items)
  end

  it 'should add no additional item' do
    fixed_item         = build_invoice_item(100, :FIXED)
    recurring_item     = build_invoice_item(150, :RECURRING)
    recurring_adj_item = build_invoice_item(-150, :ITEM_ADJ, recurring_item.id)
    fixed_adj_item     = build_invoice_item(-100, :ITEM_ADJ, fixed_item.id)
    invoice            = build_invoice([fixed_item, recurring_item, recurring_adj_item, fixed_adj_item])

    new_items = @plugin.get_additional_invoice_items(invoice, false, @properties, @call_context)
    new_items.size.should == 0

    check_idempotency(invoice, new_items)
  end

  it 'should add a single additional item' do
    fixed_item     = build_invoice_item(100, :FIXED)
    recurring_item = build_invoice_item(150, :RECURRING)
    fixed_adj_item = build_invoice_item(-100, :ITEM_ADJ, fixed_item.id)
    invoice        = build_invoice([fixed_item, recurring_item, fixed_adj_item])

    new_items = @plugin.get_additional_invoice_items(invoice, false, @properties, @call_context)
    new_items.size.should == 1

    check_invoice_item(new_items[0], 10.5, recurring_item)

    check_idempotency(invoice, new_items)
  end

  it 'should handle partial adjustments' do
    fixed_item     = build_invoice_item(100, :FIXED)
    tax_item       = build_invoice_item(7, :TAX, fixed_item.id)
    fixed_adj_item = build_invoice_item(-20, :ITEM_ADJ, fixed_item.id)
    invoice        = build_invoice([fixed_item, tax_item, fixed_adj_item])

    new_items = @plugin.get_additional_invoice_items(invoice, false, @properties, @call_context)
    new_items.size.should == 1

    check_invoice_item(new_items[0], -1.4, tax_item, :ITEM_ADJ)

    check_idempotency(invoice, new_items)
  end

  private

  def build_invoice(items)
    invoice               = Killbill::Plugin::Model::Invoice.new
    invoice.id            = SecureRandom.uuid
    invoice.invoice_items = items
    invoice
  end

  def build_invoice_item(amount, invoice_item_type=:FIXED, linked_item_id=nil)
    item                   = Killbill::Plugin::Model::InvoiceItem.new
    item.id                = SecureRandom.uuid
    item.amount            = amount
    item.invoice_item_type = invoice_item_type
    item.linked_item_id    = linked_item_id
    item
  end

  def check_invoice_item(item, amount, original_item, invoice_item_type=:TAX)
    item.should be_an_instance_of Killbill::Plugin::Model::InvoiceItem
    item.amount.should == amount
    item.invoice_item_type.should == invoice_item_type
    item.linked_item_id.should == original_item.id
  end

  def check_idempotency(original_invoice, new_items)
    invoice          = build_invoice(original_invoice.invoice_items + new_items)
    additional_items = @plugin.get_additional_invoice_items(invoice, false, @properties, @call_context)
    additional_items.size.should == 0
  end
end
