require 'spec_helper'

describe Slugforge::Configuration do

  # Use a subclass that can be safely modified without destroying other specs
  let(:described_class) do
    Class.new(Slugforge::Configuration) do
      self.configuration_files = []
    end
  end

  subject { described_class.new }

  before(:each) do
    # Ensure we have a clean configuration object for each test
    described_class.instance_variable_set(:@options, {})
  end

  describe '.option' do
    it 'defines an instance method with the option name' do
      described_class.option(:test_option, {})
      subject.should respond_to(:test_option)
    end

    it 'raies an error if a duplicate option is defined' do
      described_class.option(:test_option, {})
      expect { described_class.option(:test_option, {}) }.to raise_error
    end
  end

  describe 'programatically defined methods' do
    describe 'on the instance' do
      it 'returns the options value' do
        described_class.option(:test_option, {})
        subject.instance_variable_set(:@values, {:test_option => 'test'})
        subject.test_option.should == 'test'
      end
    end
  end

  describe "loading config" do
    let!(:option) { described_class.option(:test_option, {:default => 'test' }) }

    it 'applies default values' do
      subject.test_option.should == 'test'
    end

    context 'from conf files' do
      before(:each) do
        FakeFS.deactivate!
      end

      it "should fail with invalid YAML" do
        described_class.configuration_files = [ fixture_file("invalid_syntax.yaml") ]
        expect { subject }.to raise_error
      end

      it "should gracefully handle non-hash contents" do
        described_class.configuration_files = [ fixture_file("array.yaml") ]
        expect { subject }.to_not raise_error
      end

      context "with a missing configuration file" do
        before(:each) do
          described_class.configuration_files = [ "xxxxx.yaml" ]
        end

        it "applies the defaults" do
          subject.test_option.should == "test"
        end
      end

      context "with single configuration file" do
        let!(:option) { described_class.option(:test_option, {:default => 'test', :key => 'test'}) }

        before(:each) do
          described_class.configuration_files = [ fixture_file("valid.yaml") ]
        end

        it "should load values mapped by their configuration key" do
          subject.test_option.should == 'foo'
        end

        context "and a dotted conf key" do
          let!(:option) { described_class.option(:test_option, {:key => 'foo.bar'}) }

          it "should load nested value" do
            subject.test_option.should == 'baz'
          end
        end
      end

      context "with multiple configuration files" do
        let!(:option) { described_class.option(:test_option, {:key => 'test_option'}) }

        before(:each) do
          described_class.configuration_files = [ fixture_file("one.yaml"), fixture_file("two.yaml") ]
        end

        it "should override the values in the first file with values from the second" do
          subject.test_option.should == 2
        end

        context "and a dotted conf key" do
          let!(:option) { described_class.option(:test_option, {:key => 'foo.bar'}) }

          it "should load and override nested values" do
            subject.test_option.should == "baz"
          end
        end
      end
    end

    context "from ENV" do
      let!(:option) { described_class.option(:test_option, {:default => 'test', :key => 'test_option', :env => 'TEST_OPTION'}) }

      around(:each) do |example|
        with_env('TEST_OPTION' => 'foo') { example.run }
      end

      it 'should assign values from mapped variables' do
        subject.test_option.should == 'foo'
      end

      context "with conf file" do
        before(:each) do
          described_class.configuration_files = [ fixture_file("one.yaml") ]
        end

        it "should prefer ENV" do
          subject.test_option.should == 'foo'
        end
      end
    end

    context "from CLI options" do
      let!(:option) { described_class.option(:test_option, {:default => 'test', :option => :'test-option'}) }

      subject { described_class.new :'test-option' => 'foo' }

      it "should load value from mapped option" do
        subject.test_option.should == 'foo'
      end

      context "with ENV present" do
        let!(:option) { described_class.option(:test_option, {:default => 'test', :option => :'test-option', :env => 'TEST_OPTION'}) }

        around(:each) do |example|
          with_env('TEST_OPTION' => 'bar') { example.run }
        end

        it 'should prefer setting from CLI' do
          subject.test_option.should == 'foo'
        end
      end
    end
  end

  describe '#update_with' do
    it 'yields for every option' do
      options = {
        :a => {:key => 'a'},
        :b => {:key => 'b'}
      }

      described_class.option(:a, options[:a])
      described_class.option(:b, options[:b])
      expect { |b| subject.send(:update_with, &b) }.to yield_successive_args(options[:a], options[:b])
    end

    context 'when the block returns a value' do
      it 'updates the options value' do
        described_class.option(:a, {})
        subject.instance_variable_set(:@values, {:a => 'false'} )
        blk = proc { |c| 'true' }
        subject.send(:update_with, &blk)
        subject.a.should == 'true'
      end

      it 'same for "falsey" but not nil' do
        described_class.option(:a, {})
        subject.instance_variable_set(:@values, {:a => 'false'} )
        blk = proc { |c| false }
        subject.send(:update_with, &blk)
        subject.a.should == false
      end
    end

    context 'when the block does not return a value' do
      it 'leaves the options value as-is' do
        described_class.option(:a, {})
        subject.instance_variable_set(:@values, {:a => 'false'} )
        blk = proc { |c| nil }
        subject.send(:update_with, &blk)
        subject.a.should == 'false'
      end
    end
  end
end

