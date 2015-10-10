module Payday
  class ApprovalLine 
    attr_accessor :description, :approved
    def initialize( options = {})
      self.description = options[:description] ||= ''
      self.approved = options[:approved] ||= false
      raise ArgumentError.new("description should not be empty") if self.description.empty?
    end
    
    def approved?
      self.approved == true
    end
  end
end