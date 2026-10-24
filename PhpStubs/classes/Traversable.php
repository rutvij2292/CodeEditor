<?php

/**
 * Interface to detect if a class is traversable using foreach.
 * Abstract base interface that cannot be implemented alone.
 * Instead it must be implemented by either IteratorAggregate or Iterator.
 * @template TKey
 * @template-covariant TValue
 * @template-extends iterable<TKey, TValue>
 */
interface Traversable extends iterable
{

}
