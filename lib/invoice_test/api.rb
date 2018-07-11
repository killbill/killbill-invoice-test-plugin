module InvoiceTest

  class InvoicePlugin < Killbill::Plugin::Invoice

    # This implementation is idempotent, will apply tax on old invoices if needed
    # and automatically handle adjustments
    def get_additional_invoice_items(new_invoice, dry_run, properties, context)
      all_invoices = @kb_apis.invoice_user_api.get_invoices_by_account(new_invoice.account_id, false, false, context)
      # Workaround for https://github.com/killbill/killbill/issues/265
      all_invoices << new_invoice unless all_invoices.find { |inv| inv.id == new_invoice.id }

      existing_taxable_items    = []
      existing_tax_items        = {}
      existing_adjustment_items = {}
      all_invoices.each do |invoice|
        invoice.invoice_items.each do |invoice_item|
          existing_taxable_items << invoice_item if is_taxable_item(invoice_item)
          (existing_tax_items[invoice_item.linked_item_id] ||= []) << invoice_item if is_tax_item(invoice_item)
          (existing_adjustment_items[invoice_item.linked_item_id] ||= []) << invoice_item if is_adjustment_item(invoice_item)
        end
      end

      compute_tax_for_items(new_invoice, existing_taxable_items, existing_tax_items, existing_adjustment_items)
    end

    private

    def compute_tax_for_items(current_invoice, taxable_items, tax_items, adjustment_items)
      additional_items = taxable_items.map { |taxable_item| compute_tax_for_item(current_invoice, taxable_item, tax_items[taxable_item.id] || [], adjustment_items) }
      additional_items.compact!

      # Add all new items on the latest invoice
      additional_items.map { |ii| ii.invoice_id = current_invoice.id }

      additional_items
    end

    def compute_tax_for_item(current_invoice, taxable_item, tax_items, adjustment_items)
      current_tax_amount  = tax_items.inject(0) { |sum, tax_item| sum + net_amount(tax_item, adjustment_items) }
      expected_tax_amount = compute_tax_amount(net_amount(taxable_item, adjustment_items))

      build_missing_item(current_invoice, current_tax_amount, expected_tax_amount, taxable_item, tax_items, adjustment_items)
    end

    def build_missing_item(current_invoice, current_tax_amount, expected_tax_amount, taxable_item, tax_items, adjustment_items)
      if current_tax_amount < expected_tax_amount
        # Add missing TAX item
        build_tax_item(taxable_item, expected_tax_amount - current_tax_amount)
      elsif current_tax_amount > expected_tax_amount
        # Item adjust the TAX item
        adjustment_amount  = current_tax_amount - expected_tax_amount
        tax_item_to_adjust = find_tax_item_to_adjust(tax_items, adjustment_items, adjustment_amount)
        build_adjustment_item(current_invoice, tax_item_to_adjust, adjustment_amount)
      else
        # Nothing to do
        nil
      end
    end

    def build_tax_item(original_item, amount)
      rounded_amount = amount.round(2)
      return nil if rounded_amount == 0
      build_item(original_item, rounded_amount, 'Tax item', :TAX)
    end

    def build_adjustment_item(current_invoice, item_to_adjust, amount)
      rounded_amount = amount.round(2)
      return nil if rounded_amount == 0
      item = build_item(item_to_adjust, -rounded_amount, 'Tax item', :ITEM_ADJ)
      item.start_date = current_invoice.invoice_date
      item.end_date = nil
      item
    end

    def compute_tax_amount(net_taxable_amount)
      net_taxable_amount * 7.0 / 100
    end

    def find_tax_item_to_adjust(tax_items, adjustment_items, amount_to_adjust)
      tax_items.find { |tax_item| net_amount(tax_item, adjustment_items) >= amount_to_adjust }
    end

    def net_amount(invoice_item, adjustment_items)
      invoice_item.amount + sum(adjustment_items[invoice_item.id])
    end

    def sum(invoice_items)
      (invoice_items || []).inject(0) { |sum, ii| sum + ii.amount }
    end

    def is_taxable_item(invoice_item)
      invoice_item.amount > 0 and [:EXTERNAL_CHARGE, :FIXED, :RECURRING, :USAGE].include?(invoice_item.invoice_item_type)
    end

    def is_tax_item(invoice_item)
      invoice_item.invoice_item_type == :TAX
    end

    def is_adjustment_item(invoice_item)
      [:ITEM_ADJ, :REPAIR_ADJ].include?(invoice_item.invoice_item_type)
    end
  end
end
