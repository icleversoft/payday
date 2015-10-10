require 'spec_helper'

module Payday
  describe ApprovalLine do
    let(:la){ApprovalLine.new(description:'foo')}
    it "responds to bot description and approved props" do
      expect(la).to respond_to(:description)
      expect(la).to respond_to(:approved)
    end
    
    it "description is a String" do
      expect(la.description).to be_a String
    end
    
    it "approved by default is false" do
      expect(la.approved).to be_falsey
    end
    
    it "raises an error when none description is provided" do
      expect{ApprovalLine.new}.to raise_error
    end
    
    it "responds on every property update" do
      expect(la.description).to eq('foo')
      la.description = 'lala'
      la.approved = true
      expect(la.description).to eq('lala')
      expect(la.approved).to be_truthy
      expect(la.approved?).to be_truthy
    end
  end
end
  
  