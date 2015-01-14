module InvoiceTest

  class InvoicePlugin < Killbill::Plugin::Invoice

    def get_additional_invoice_items(invoice, properties, context)
      additional_items = []
      invoice.invoice_items.each do |original_item|
        additional_items << build_item(original_item, original_item.amount * 7 / 100, 'Tax item', :TAX) unless original_item.amount == 0
      end

      additional_items
    end
  end
end
