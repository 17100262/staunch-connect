module EnvHelpers
  # Temporarily sets (or with nil, unsets) environment variables for the block.
  def with_env(vars)
    original = vars.keys.to_h { |key| [ key, ENV[key] ] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

RSpec.configure { |config| config.include EnvHelpers }
