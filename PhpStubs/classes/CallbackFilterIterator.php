<?php

/**
 * Filtered iterator using the callback to determine which items are accepted or rejected.
 * @since 5.4
 */
class CallbackFilterIterator extends FilterIterator
{
    /**
     * Creates a filtered iterator using the callback to determine which items are accepted or rejected.
     * @param Iterator $iterator The iterator to be filtered.
     * @param callable $callback The callback, which should return TRUE to accept the current item or FALSE otherwise. May be any valid callable value. The callback should accept up to three arguments: the current item, the current key and the iterator, respectively. function my_callback($current, $key, ...
     */
    public function __construct(Iterator $iterator, callable $callback) {}

    /**
     * This method calls the callback with the current value, current key and the inner iterator.
     * The callback is expected to return TRUE if the current item is to be accepted, or FALSE otherwise.
     * @return bool true if the current element is acceptable, otherwise false.
     */
    public function accept(): bool {}
}
