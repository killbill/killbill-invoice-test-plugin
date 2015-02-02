module InvoiceTest

  class InvoicePlugin < Killbill::Plugin::Invoice

    def get_additional_invoice_items(invoice, properties, context)
      additional_items = []
      invoice.invoice_items.each do |original_item|
        if original_item.amount > 0 and [:EXTERNAL_CHARGE, :FIXED, :RECURRING, :USAGE].include?(original_item.invoice_item_type)
          current_tax_amount  = total_taxed_amount_for_item(invoice, original_item).round(2)
          expected_tax_amount = compute_tax_amount(invoice, original_item).round(2)
          if current_tax_amount < expected_tax_amount
            # Add missing TAX item
            additional_items << build_item(original_item, expected_tax_amount - current_tax_amount, 'Tax item', :TAX)
          elsif current_tax_amount > expected_tax_amount
            # Item adjust the TAX item
            adjustment_amount  = (current_tax_amount - expected_tax_amount).round(2)
            tax_item_to_adjust = find_tax_item_to_adjust(invoice, original_item, adjustment_amount)
            additional_items << build_item(tax_item_to_adjust, -adjustment_amount, 'Tax item', :ITEM_ADJ)
          end
        end
      end

      additional_items
    end

    private

    def compute_tax_amount(original_invoice, original_item)
      net_amount(original_invoice, original_item) * 7.0 / 100
    end

    def find_tax_item_to_adjust(original_invoice, original_item, amount_to_adjust)
      original_invoice.invoice_items.find do |ii|
        ii.linked_item_id == original_item.id and ii.invoice_item_type == :TAX and net_amount(original_invoice, ii) >= amount_to_adjust
      end
    end

    # Positive or null amount
    def total_taxed_amount_for_item(original_invoice, original_item)
      original_invoice.invoice_items.inject(0) do |sum, ii|
        if ii.linked_item_id == original_item.id and ii.invoice_item_type == :TAX
          sum + net_amount(original_invoice, ii)
        else
          sum
        end
      end
    end

    def net_amount(original_invoice, original_item)
      original_item.amount + total_adjusted_amount_for_item(original_invoice, original_item)
    end

    # Negative amount
    def total_adjusted_amount_for_item(original_invoice, original_item)
      original_invoice.invoice_items.inject(0) do |sum, ii|
        if ii.linked_item_id == original_item.id and [:ITEM_ADJ, :REPAIR_ADJ].include?(ii.invoice_item_type)
          sum + ii.amount
        else
          sum
        end
      end
    end
  end
end
