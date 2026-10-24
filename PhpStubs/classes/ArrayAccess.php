<?php

/**
 * Interface to provide accessing objects as arrays.
 * @template TKey
 * @template TValue
 */
interface ArrayAccess
{
    /**
     * Whether a offset exists
     * @param TKey $offset An offset to check for.
     * @return bool true on success or false on failure. The return value will be casted to boolean if non-boolean was returned.
     */
    public function offsetExists(mixed $offset): bool;

    /**
     * Offset to retrieve
     * @param TKey $offset The offset to retrieve.
     * @return TValue Can return all value types.
     */
    public function offsetGet(mixed $offset): mixed;

    /**
     * Offset to set
     * @param TKey $offset The offset to assign the value to.
     * @param TValue $value The value to set.
     * @return void No value is returned.
     */
    public function offsetSet(
        mixed $offset,
        mixed $value
    ): void;

    /**
     * Offset to unset
     * @param TKey $offset The offset to unset.
     * @return void No value is returned.
     */
    public function offsetUnset(mixed $offset): void;
}
