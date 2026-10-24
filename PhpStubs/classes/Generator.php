<?php

/**
 * Generator objects are returned from generators, cannot be instantiated via new.
 * @template-covariant TKey
 * @template-covariant TYield
 * @template TSend
 * @template-covariant TReturn
 * @template-implements Iterator<TKey, TYield>
 */
final class Generator implements Iterator
{
    /**
     * Throws an exception if the generator is currently after the first yield.
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Returns false if the generator has been closed, true otherwise.
     * @return bool Returns false if the iterator has been closed. Otherwise returns true.
     */
    public function valid(): bool {}

    /**
     * Returns whatever was passed to yield or null if nothing was passed or the generator is already closed.
     * @return TYield|null Returns the yielded value.
     */
    public function current(): mixed {}

    /**
     * Returns the yielded key or, if none was specified, an auto-incrementing key or null if the generator is already closed.
     * @return TKey|null Returns the yielded key.
     */
    public function key(): mixed {}

    /**
     * Resumes the generator (unless the generator is already closed).
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Sets the return value of the yield expression and resumes the generator (unless the generator is already closed).
     * @param TSend $value Value to send into the generator. This value will be the return value of the yield expression the generator is currently at.
     * @return TYield|null Returns the yielded value.
     */
    public function send(mixed $value): mixed {}

    /**
     * Throws an exception at the current suspension point in the generator.
     * @param Throwable $exception
     * @return TYield
     */
    public function PS_UNRESERVE_PREFIX_throw(Throwable $exception): mixed {}

    /**
     * Returns whatever was passed to return or null if nothing.
     * Throws an exception if the generator is still valid.
     * @return TReturn Returns the generator's return value once it has finished executing.
     * @since 7.0
     */
    public function getReturn(): mixed {}

    /**
     * Serialize callback
     * Throws an exception as generators can't be serialized.
     * @return void No value is returned.
     */
    public function __wakeup() {}

    /**
     * @since 8.4
     */
    public function __debugInfo(): array {}
}
