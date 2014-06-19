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

    shared_examples_for "a deployment method" do
      it "should succeed" do
        begin
          result["success"].should == true
        rescue SystemExit
          fail stderr.string
        end
      end
    end

    describe "#file" do
      let(:operation) { "file" }
      let(:target)    { "artifact.slug" }

      it_should_behave_like "a deployment method"
    end

    describe "#tag" do
      let(:operation) { "tag" }
      let(:target)    { "testing" }

      context "with existing tagged slug" do
        before(:each) do
          slug = "123.slug"
          create_slug project, slug
          create_tag project, target, slug
        end

        it_should_behave_like "a deployment method"
      end
    end

    describe "#name" do
      let(:operation) { "name" }
      let(:target)    { "123456" }

      context "with existing named slug" do
        before(:each) do
          create_slug project, "#{target}.slug"
        end

        it_should_behave_like "a deployment method"
      end
    end
  end

end
