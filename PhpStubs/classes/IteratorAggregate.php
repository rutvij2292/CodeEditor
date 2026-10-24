<?php

/**
 * Interface to create an external Iterator.
 * @template TKey
 * @template-covariant TValue
 * @template-extends Traversable<TKey, TValue>
 */
interface IteratorAggregate extends Traversable
{
    /**
     * Retrieve an external iterator
     * @return Traversable<TKey, TValue>|TValue[] An instance of an object implementing Iterator or Traversable
     * @throws Exception on failure.
     */
    public function getIterator(): Traversable;
}
