require 'spec_helper'

describe Slugforge::Command do
  let(:command_class) { Class.new(Slugforge::Command) }
  let(:stdout)        { StringIO.new }
  let(:stderr)        { StringIO.new }
  let(:args)          { [] }
  let(:command)       { capture(:stdout, stdout) { capture(:stderr, stderr) { command_class.start(args) } } }

  describe "slugin loading" do
    context "in a command" do
      it "should only activate slugins once" do
        Slugforge::SluginManager.any_instance.should_receive(:activate_slugins).once
          command
      end
    end

    context "in a subcommand" do
      let(:subcommand_class) { Class.new(Slugforge::SubCommand) }
      let(:args) { [ 'sub' ] }

      before(:each) do
        command_class.desc 'sub [THING]', 'test subcommand'
        command_class.subcommand 'sub', subcommand_class
      end

      it "should only activate slugins once" do
        Slugforge::SluginManager.any_instance.should_receive(:activate_slugins).once
        command
      end
    end
  end
end
