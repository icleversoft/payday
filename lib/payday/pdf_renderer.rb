module Payday
  # The PDF renderer. We use this internally in Payday to render pdfs, but really you should just need to call
  # {{Payday::Invoiceable#render_pdf}} to render pdfs yourself.
  class PdfRenderer
    MAX_LOGO_DIM = 150
    # Renders the given invoice as a pdf on disk
    def self.render_to_file(invoice, path)
      pdf(invoice).render_file(path)
    end

    # Renders the given invoice as a pdf, returning a string
    def self.render(invoice)
      pdf(invoice).render
    end

    private

    def self.pdf(invoice)
      pdf = Prawn::Document.new(page_size: invoice_or_default(invoice, :page_size))

      # set up some default styling
      pdf.font_size(8)

      stamp(invoice, pdf)
      company_banner(invoice, pdf)
      bill_to_ship_to(invoice, pdf)
      # invoice_details(invoice, pdf)
      line_items_table(invoice, pdf)
      totals_lines(invoice, pdf)
      notes(invoice, pdf)
      
      if invoice.has_approval_items?
        pdf.start_new_page
        company_banner(invoice, pdf)
        aprroved_lines( invoice, pdf)
      end
      
      page_numbers(pdf)

      pdf
    end

    class << self
      def aprroved_lines( invoice, pdf )
        # table_data << [bold_cell(pdf, I18n.t("payday.line_item.description", default: "Description"), borders: []),
        #                bold_cell(pdf, I18n.t("payday.line_item.amount", default: "Amount"), align: :right, borders: [])]
         # [pdf.bounds.right - 18, -15]
        # pdf.move_cursor_to(pdf.cursor - 20)
        # pdf.move_cursor_to(pdf.bounds.bottom)
        check = invoice_or_default(invoice, :check)
        no_check = invoice_or_default(invoice, :no_check)
        
        invoice.approved_items.each do |line|
          table_data = []
          table_data << [bold_cell(pdf, line.description, size: 10), 
            {image: line.approved? ? check : no_check  , image_height: 30}]
          pdf.move_cursor_to(pdf.cursor - 10)
          pdf.table(table_data, width: pdf.bounds.width, header: false,
                    cell_style: { border_width: 0.0, border_color: "cccccc",
                                  padding: [5, 5] },
                    row_colors: %w(ffffff ffffff)) do

            natural = natural_column_widths
            natural[0] = width - natural[1]
            
            column_widths = natural
          end
        end

      end
    end

    def self.stamp(invoice, pdf)
      stamps = invoice_or_default(invoice, :stamps)
      if invoice.refunded?
        stamp = stamps[:refunded]
      elsif invoice.paid?
        stamp = stamps[:paid]
      elsif invoice.overdue?
        stamp = stamps[:overdue]
      end
      
      # stamp = nil
      # if invoice.refunded?
      #   stamp = I18n.t "payday.status.refunded", default: "REFUNDED"
      # elsif invoice.paid?
      #   stamp = I18n.t "payday.status.paid", default: "PAID"
      # elsif invoice.overdue?
      #   stamp = I18n.t "payday.status.overdue", default: "OVERDUE"
      # end
      if stamp && File.exist?(stamp)
        # width, height = IO.read(stamp)[0x10..0x18].unpack('NN')
        width, height = [120, 88]
        # logo_info = pdf.image(stamp, at: pdf.bounds.top_left, width: width, height: height)
        # logo_info = pdf.image(stamp, at: [(pdf.bounds.width - (width * 0.45))/2, pdf.bounds.top - 30], scale: 0.45)
        logo_info = pdf.image(stamp, at: [(pdf.bounds.width - width)/2, pdf.bounds.top - 30], width: width, height: height)
        logo_height = logo_info.scaled_height
        
        # pdf.bounding_box([150, pdf.cursor - 50], width: pdf.bounds.width - 300) do
        #   pdf.font("Helvetica-Bold") do
        #     pdf.fill_color "cc0000"
        #     pdf.text stamp, align: :center, size: 25, rotate: 15
        #   end
        # end
      end

      # pdf.fill_color "000000"
    end

    def self.company_banner(invoice, pdf)
      # render the logo
      image = invoice_or_default(invoice, :invoice_logo)
      height = nil
      width = nil

      # Handle images defined with a hash of options
      if image.is_a?(Hash)
        data = image
        image = data[:filename]
        width, height = data[:size].split("x").map(&:to_f) unless data[:size].nil?
      end

      if width.nil? && height.nil? && image.is_a?(String)
        width, height = FastImage.size( image )
      end

      width, height = [100, 100] if width.nil? && height.nil?

      width, height = fix_logo_dimensions( [width, height])
      
      if File.extname(image) == ".svg"
        logo_info = pdf.svg(File.read(image), at: pdf.bounds.top_left, width: width, height: height)
        logo_height = logo_info[:height]
      else
        logo_info = pdf.image(image, at: pdf.bounds.top_left, width: width, height: height)
        logo_height = logo_info.scaled_height
      end

      # render the company details
      table_data = []
      table_data << [bold_cell(pdf, invoice_or_default(invoice, :company_name).strip, size: 12)]

      invoice_or_default(invoice, :company_details).lines.each { |line| table_data << [line] }

      table = pdf.make_table(table_data, cell_style: { borders: [], padding: 0 })
      pdf.bounding_box([pdf.bounds.width - table.width, pdf.bounds.top], width: table.width, height: table.height + 5) do
        table.draw
      end

      pdf.move_cursor_to(pdf.bounds.top - logo_height - 20)
    end

    def self.bill_to_ship_to(invoice, pdf)
      bill_to_cell_style = { borders: [], padding: [2, 0] }
      bill_to_ship_to_bottom = 0

      # render bill to
      pdf.float do
        table = pdf.table([[bold_cell(pdf, I18n.t("payday.invoice.bill_to", default: "Bill To"))],
                           [invoice.bill_to]], column_widths: [200], cell_style: bill_to_cell_style)
        bill_to_ship_to_bottom = pdf.cursor
      end

      table_data = []
      #Invoice Number
      table_data << [bold_cell(pdf, "INVOICE #:", {align: :right, size: 10}), 
                     bold_cell(pdf, invoice.invoice_number, {align: :left, size: 10, valign: :top})]
                     
     if defined?( invoice.for_period ) && invoice.for_period.size == 2
       #Paid By
       range = " - "
       if !invoice.for_period[0].is_a?(String)
         range = "#{invoice.for_period[0].strftime("%m/%d/%Y")} - #{invoice.for_period[1].strftime("%m/%d/%Y")}"
       else
         range =  invoice.for_period.join(" - ")
       end
       table_data << [bold_cell(pdf, "For service provided on dates: ", {align: :right}), 
                      cell(pdf, range, {align: :left})]
     end
      #Due date
      if defined?(invoice.due_at) and !invoice.due_at.nil?
        table_data << [bold_cell(pdf, I18n.t("payday.invoice.due_date", default: "Due Date"), {align: :right}), 
                        cell(pdf, invoice.due_at.strftime("%B %d, %Y"), {align: :left})]
      end
      unless invoice.paid_at.nil?
        #Paid On
        table_data << [bold_cell(pdf, "Paid on: ", {align: :right}), 
                       cell(pdf, invoice.paid_at.strftime("%B %d, %Y"), {align: :left})]
        
        if defined?( invoice.paid_by )
          #Paid By
          table_data << [bold_cell(pdf, "By: ", {align: :right}), 
                         cell(pdf, invoice.paid_by, {align: :left})]
        end
        if defined?( invoice.paid_with )
          #Paid with
          table_data << [bold_cell(pdf, "with: ", {align: :right}), 
                         cell(pdf, invoice.paid_with, {align: :left})]
        end
      end
      
      table = pdf.make_table( table_data, column_widths: [170, 100], cell_style: { borders: [], padding: [2, 5, 0, 0] })
      pdf.bounding_box([pdf.bounds.width - table.width, pdf.cursor], width: table.width, height: table.height + 2) do
        table.draw
      end
      
      # # render ship to
      # if defined?(invoice.ship_to) && !invoice.ship_to.nil?
      #   table = pdf.make_table([[bold_cell(pdf, I18n.t("payday.invoice.ship_to", default: "Ship To"))],
      #                           [invoice.ship_to]], column_widths: [200], cell_style: bill_to_cell_style)
      # 
      #   pdf.bounding_box([pdf.bounds.width - table.width, pdf.cursor], width: table.width, height: table.height + 2) do
      #     table.draw
      #   end
      # end
      # 
      # make sure we start at the lower of the bill_to or ship_to details
      bill_to_ship_to_bottom = pdf.cursor if pdf.cursor < bill_to_ship_to_bottom
      pdf.move_cursor_to(bill_to_ship_to_bottom - 20)
    end

    def self.invoice_details(invoice, pdf)
      # invoice details
      table_data = []

      # invoice number
      if defined?(invoice.invoice_number) && invoice.invoice_number
        table_data << [bold_cell(pdf, I18n.t("payday.invoice.invoice_no", default: "Invoice #:")),
                       bold_cell(pdf, invoice.invoice_number.to_s, align: :right)]
      end

      # invoice date
      if defined?(invoice.invoice_date) && invoice.invoice_date
        if invoice.invoice_date.is_a?(Date) || invoice.invoice_date.is_a?(Time)
          invoice_date = invoice.invoice_date.strftime(Payday::Config.default.date_format)
        else
          invoice_date = invoice.invoice_date.to_s
        end

        table_data << [bold_cell(pdf, I18n.t("payday.invoice.invoice_date", default: "Invoice Date:")),
                       bold_cell(pdf, invoice_date, align: :right)]
      end

      # Due on
      if defined?(invoice.due_at) && invoice.due_at
        if invoice.due_at.is_a?(Date) || invoice.due_at.is_a?(Time)
          due_date = invoice.due_at.strftime(Payday::Config.default.date_format)
        else
          due_date = invoice.due_at.to_s
        end

        table_data << [bold_cell(pdf, I18n.t("payday.invoice.due_date", default: "Due Date:")),
                       bold_cell(pdf, due_date, align: :right)]
      end

      # Paid on
      if defined?(invoice.paid_at) && invoice.paid_at
        if invoice.paid_at.is_a?(Date) || invoice.paid_at.is_a?(Time)
          paid_date = invoice.paid_at.strftime(Payday::Config.default.date_format)
        else
          paid_date = invoice.paid_at.to_s
        end

        table_data << [bold_cell(pdf, I18n.t("payday.invoice.paid_date", default: "Paid Date:")),
                       bold_cell(pdf, paid_date, align: :right)]
      end

      # Refunded on
      if defined?(invoice.refunded_at) && invoice.refunded_at
        if invoice.refunded_at.is_a?(Date) || invoice.refunded_at.is_a?(Time)
          refunded_date = invoice.refunded_at.strftime(Payday::Config.default.date_format)
        else
          refunded_date = invoice.refunded_at.to_s
        end

        table_data << [bold_cell(pdf, I18n.t("payday.invoice.refunded_date", default: "Refunded Date:")),
                       bold_cell(pdf, refunded_date, align: :right)]
      end

      # loop through invoice_details and include them
      invoice.each_detail do |key, value|
        table_data << [bold_cell(pdf, key),
                       bold_cell(pdf, value, align: :right)]
      end

      if table_data.length > 0
        pdf.table(table_data, cell_style: { borders: [], padding: [1, 10, 1, 1] })
      end
    end

    def self.line_items_table(invoice, pdf)
      table_data = []
      table_data << [bold_cell(pdf, I18n.t("payday.line_item.description", default: "Description"), borders: []),
                     bold_cell(pdf, I18n.t("payday.line_item.unit_price", default: "Unit Price"), align: :center, borders: []),
                     bold_cell(pdf, I18n.t("payday.line_item.quantity", default: "Quantity"), align: :center, borders: []),
                     bold_cell(pdf, I18n.t("payday.line_item.amount", default: "Amount"), align: :center, borders: [])]
      invoice.line_items.each do |line|
        table_data << [line.description,
                       (line.display_price || number_to_currency(line.price, invoice)),
                       (line.display_quantity || BigDecimal.new(line.quantity.to_s).to_s("F")),
                       number_to_currency(line.amount, invoice)]
      end

      pdf.move_cursor_to(pdf.cursor - 20)
      pdf.table(table_data, width: pdf.bounds.width, header: true,
                cell_style: { border_width: 0.5, border_color: "cccccc",
                              padding: [5, 10] },
                row_colors: %w(dfdfdf ffffff)) do

        # left align the number columns
        columns(1..3).rows(1..row_length - 1).style(align: :right)

        # set the column widths correctly
        natural = natural_column_widths
        natural[0] = width - natural[1] - natural[2] - natural[3]

        column_widths = natural
      end
    end

    def self.totals_lines(invoice, pdf)
      table_data = []
      table_data << [
        bold_cell(pdf, I18n.t("payday.invoice.subtotal", default: "Subtotal:")),
        cell(pdf, number_to_currency(invoice.subtotal, invoice), align: :right)
      ]
      
      invoice.fee_items.each do |descr, val|
        table_data << [
          bold_cell(pdf, "#{descr}:", align: :right, borders: [1,1,1,1]),
          # bold_cell(pdf, "#{descr}:"),
          cell(pdf, number_to_currency(val.to_f, invoice), align: :right)
        ]
      end
      # if invoice.tax_rate > 0
      #   if invoice.tax_description.nil?
      #     tax_description = I18n.t("payday.invoice.tax", default: "Tax:")
      #   else
      #     tax_description = invoice.tax_description
      #   end
      # 
      #   table_data << [
      #     bold_cell(pdf, tax_description),
      #     cell(pdf, number_to_currency(invoice.tax, invoice), align: :right)
      #   ]
      # end
      if invoice.shipping_rate > 0
        if invoice.shipping_description.nil?
          shipping_description =
            I18n.t("payday.invoice.shipping", default: "Shipping:")
        else
          shipping_description = invoice.shipping_description
        end

        table_data << [
          bold_cell(pdf, shipping_description),
          cell(pdf, number_to_currency(invoice.shipping, invoice),
               align: :right)
        ]
      end

      
      table_data << [
        bold_cell(pdf, I18n.t("payday.invoice.total", default: "Total:"),
                  size: 12),
        cell(pdf, number_to_currency(invoice.total, invoice),
             size: 12, align: :right)
      ]


      table = pdf.make_table(table_data, cell_style: { borders: [] })
      pdf.bounding_box([pdf.bounds.width - table.width, pdf.cursor],
                       width: table.width, height: table.height + 2) do

        table.draw
        pdf.line_width = 0.8
        pdf.stroke_color = "000000"
        pdf.stroke_line([0, pdf.cursor + 24, pdf.bounds.width, pdf.cursor + 24 ])
        pdf.move_cursor_to(pdf.cursor)
      end
    end

    def self.notes(invoice, pdf)
      if defined?(invoice.notes) && invoice.notes
        pdf.move_cursor_to(pdf.cursor - 30)
        pdf.font("Helvetica-Bold") do
          pdf.text(I18n.t("payday.invoice.notes", default: "Notes"))
        end
        pdf.line_width = 0.5
        pdf.stroke_color = "cccccc"
        pdf.stroke_line([0, pdf.cursor - 3, pdf.bounds.width, pdf.cursor - 3])
        pdf.move_cursor_to(pdf.cursor - 10)
        pdf.text(invoice.notes.to_s)
      end
    end

    def self.page_numbers(pdf)
      if pdf.page_count > 1
        pdf.number_pages("<page> / <total>", at: [pdf.bounds.right - 18, -15])
      end
    end

    def self.invoice_or_default(invoice, property)
      if invoice.respond_to?(property) && invoice.send(property)
        invoice.send(property)
      else
        Payday::Config.default.send(property)
      end
    end

    def self.cell(pdf, text, options = {})
      Prawn::Table::Cell::Text.make(pdf, text, options)
    end

    def self.bold_cell(pdf, text, options = {})
      cell(pdf, "<b>#{text}</b>", options.merge(inline_format: true))
    end

    # Converts this number to a formatted currency string
    def self.number_to_currency(number, invoice)
      currency = Money::Currency.wrap(invoice_or_default(invoice, :currency))
      number *= currency.subunit_to_unit
      number = number.round unless Money.infinite_precision
      Money.new(number, currency).format
    end

    def self.max_cell_width(cell_proxy)
      max = 0
      cell_proxy.each do |cell|
        max = cell.natural_content_width if cell.natural_content_width > max
      end
      max
    end
    
    def self.fix_logo_dimensions( dimensions )
      width, height = dimensions
      if width > MAX_LOGO_DIM || height > MAX_LOGO_DIM
        ar = width.to_f / height.to_f
        if width > height
          width = MAX_LOGO_DIM
          height = width / ar
        elsif
          height = MAX_LOGO_DIM
          width = ar * height
        else
          width = height = MAX_LOGO_DIM
        end
      end
      [width, height]
    end
  end
end
