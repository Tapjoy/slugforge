def sanitize_environment! (pattern)
  ENV.keys.select { |k| k =~ pattern }.each { |k| ENV[k] = nil }
end
