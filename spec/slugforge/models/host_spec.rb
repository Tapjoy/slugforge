describe Slugforge::Host do
  subject { Slugforge::Host.new('x') }

  let(:slug_name) { 'slug_name.slug' }
  let(:logger)    { MockLogger.new }
  let(:opts)      { {} }

  it 'should notify on install.completed' do
    subject.stub(:ssh_command).and_return({:output => '', :exit_code => 0})
    expect{ subject.send(:install_slug, nil, slug_name, logger, opts) }.to instrument('install.completed')
  end
end

