module Payday
  class ImageDims
    attr_accessor :width, :height
    def initialize( file_name )
      @width, @height = [nil, nil]
      case File.extname(file_name).downcase
        when ".png"
          self.width, self.height = png_dims( file_name )
        when ".gif"
          self.width, self.height = gif_dims( file_name )
        when ".jpg"
          File.open(file_name, 'rb') { |io| examine(io) }
      end
    end
    
    private
    def png_dims( file_name)
      IO.read( file_name )[0x10..0x18].unpack('NN')
    end
  
    def gif_dims( file_name )
      IO.read('image.gif')[6..10].unpack('SS')
    end

    def examine(io)
      return unless io.getc == 0xFF && io.getc == 0xD8 # SOI
      
      # raise 'malformed JPEG' unless io.getc == 0xFF && io.getc == 0xD8 # SOI
    
      class << io
        def readint; (readchar << 8) + readchar; end
        def readframe; read(readint - 2); end
        def readsof; [readint, readchar, readint, readint, readchar]; end
        def next
          c = readchar while c != 0xFF
          c = readchar while c == 0xFF
          c
        end
      end
    
      while marker = io.next
        case marker
          when 0xC0..0xC3, 0xC5..0xC7, 0xC9..0xCB, 0xCD..0xCF # SOF markers
            length, bits, @height, @width, components = io.readsof
            raise 'malformed JPEG' unless length == 8 + components * 3
          when 0xD9, 0xDA 
            break # EOI, SOS
          when 0xFE        
            comment = io.readframe # COM
          when 0xE1        
            io.readframe # APP1, contains EXIF tag
          else              
            io.readframe # ignore frame
        end
      end   
    end 
  end
end