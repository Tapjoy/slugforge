require 'spec_helper'
require 'json'

describe Slugforge::Commands::Deploy, :config => true do

  describe "deployment via" do
    let(:project)   { "zany" }
    let(:host)      { "example.com" }
    let(:opts)      { %w(--force --json) }
    let(:config)    { %w() }
    let(:cmd)       { ["deploy", operation, target, "--project", project, host, opts, config].flatten }
    let(:stdout)    { StringIO.new }
    let(:stderr)    { StringIO.new }
    let(:output)    { capture(:stdout, stdout) { capture(:stderr, stderr) { Slugforge::Cli.start(cmd) } } }
    let(:result)    { JSON.parse(output) }
    let(:s3_root)   { "s3://#{helpers.config.values[:slug_bucket]}/#{project}" }

    shared_examples_for "a deployment method" do
      it "should succeed" do
        begin
          result["success"].should == true
        rescue SystemExit
          fail stderr.string
        end
      end

      it "has a full slug path" do
        Slugforge::Commands::Deploy.any_instance.should_receive(:deploy).with(anything, anything, hash_including(locator))
        output
      end
    end

    describe "#file" do
      let(:operation) { "file" }
      let(:target)    { "artifact.slug" }
      let(:locator)   { {:filename => target} }

      it_should_behave_like "a deployment method"
    end

    describe "#tag" do
      let(:operation) { "tag" }
      let(:target)    { "testing" }
      let(:slug_name) { "123.slug" }
      let(:locator)   { {:s3_url => "#{s3_root}/#{slug_name}"} }

      context "with existing tagged slug" do
        before(:each) do
          create_slug project, slug_name
          create_tag project, target, slug_name
        end

        it_should_behave_like "a deployment method"
      end
    end

    describe "#name" do
      let(:operation) { "name" }
      let(:target)    { "123456" }
      let(:locator)   { {:s3_url => "#{s3_root}/#{target}.slug"} }

      context "with existing named slug" do
        before(:each) do
          create_slug project, "#{target}"
        end

        it_should_behave_like "a deployment method"
      end
    end
  end

end
