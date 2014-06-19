RSpec.configure do |config|
  config.before(:each) do
    Net::SSH.stub(:start) do |ip, user, options, &block|
      block.call double("ssh connection", :exec! => "", :options => { :user => user })
    end
    Net::SCP.stub(:upload!)
  end
end
