module Enumerable
  def parallel_map
    queue = Queue.new

    self.map do |item|
      Thread.new do
        # NOTE: You can not do anything that is not thread safe in this block...
        queue << yield(item)
      end
    end.each(&:join)

    [].tap do |results|
      results << queue.pop until queue.empty?
    end
  end

  def parallel_map_with_index
    queue = Queue.new

    self.map.with_index do |item, index|
      Thread.new do
        # NOTE: You can not do anything that is not thread safe in this block...
        queue << yield(item, index)
      end
    end.each(&:join)

    [].tap do |results|
      results << queue.pop until queue.empty?
    end
  end

  def ordered_parallel_map
    queue = Queue.new

    self.map.with_index do |item, index|
      Thread.new do
        # NOTE: You can not do anything that is not thread safe in this block...
        queue << [index, yield(item)]
      end
    end.each(&:join)

    [].tap do |results|
      results << queue.pop until queue.empty?
    end.sort.map {|index, item| item }
  end
end
