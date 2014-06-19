RSpec.configure do |config|
  config.before(:all) do
    Fog.mock!
    Fog::Mock.delay = 0
  end

  config.before(:each) do
    # Fog does not provide STS mocks yet
    ::Fog::AWS::STS.stub(:new) {
      double(::Fog::AWS::STS,
        :get_session_token => build_sts_response,
        :get_federation_token => build_sts_response)
    }
  end
end
