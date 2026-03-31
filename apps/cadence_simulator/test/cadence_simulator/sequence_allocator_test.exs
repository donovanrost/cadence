defmodule CadenceSimulator.SequenceAllocatorTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.SequenceAllocator

  test "allocates independent sequences per apid" do
    allocator = SequenceAllocator.new([1, 2])

    assert SequenceAllocator.next(allocator, 1) == 0
    assert SequenceAllocator.next(allocator, 1) == 1
    assert SequenceAllocator.next(allocator, 2) == 0
    assert SequenceAllocator.peek(allocator, 1) == 2
    assert SequenceAllocator.peek(allocator, 2) == 1
  end

  test "wraps at 14-bit sequence space" do
    allocator = SequenceAllocator.new([7])

    Enum.each(1..16_383, fn _ -> SequenceAllocator.next(allocator, 7) end)

    assert SequenceAllocator.next(allocator, 7) == 16_383
    assert SequenceAllocator.next(allocator, 7) == 0
  end
end
