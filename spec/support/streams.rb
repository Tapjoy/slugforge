def capture(stream, buffer = StringIO.new)
  begin
    stream = stream.to_s
    eval "$#{stream} = buffer"
    yield
    result = eval("$#{stream}").string
  ensure
    eval("$#{stream} = #{stream.upcase}")
  end

  result
end
alias :silence :capture
