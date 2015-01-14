require 'spec_helper'
require 'logger'

describe InvoiceTest::InvoicePlugin do
  before(:each) do

    kb_apis         = Killbill::Plugin::KillbillApi.new('killbill-invoice-test', {})
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

  it 'should add additional item' do
    item        = Killbill::Plugin::Model::InvoiceItem.new
    item.id     = SecureRandom.uuid
    item.amount = 100

    invoice               = Killbill::Plugin::Model::Invoice.new
    invoice.id            = SecureRandom.uuid
    invoice.invoice_items = [item]

    new_items = @plugin.get_additional_invoice_items(invoice, @properties, @call_context)
    new_items.size.should == 1

    new_item = new_items.first
    new_item.should be_an_instance_of Killbill::Plugin::Model::InvoiceItem
    new_item.amount.should == 7
    new_item.invoice_item_type.should == :TAX
    new_item.linked_item_id.should == item.id
  end
end
