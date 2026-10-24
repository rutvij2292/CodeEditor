<?php

/**
 * The Seekable iterator.
 * @template TKey
 * @template-covariant TValue
 * @template-extends Iterator<TKey, TValue>
 */
interface SeekableIterator extends Iterator
{
    /**
     * Seeks to a position
     * @param int $offset The position to seek to.
     * @return void No value is returned.
     * @throws \OutOfBoundsException Implementations should throw an OutOfBoundsException if the offset is not seekable.
     */
    public function seek(int $offset): void;
}
