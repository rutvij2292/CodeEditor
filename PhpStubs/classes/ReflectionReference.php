<?php

/**
 * The ReflectionReference class provides information about a reference.
 *
 * Note: Unlike the description in the documentation, the class itself is not final.
 * @since 7.4
 */
final class ReflectionReference
{
    /**
     * ReflectionReference cannot be created explicitly.
     */
    private function __construct() {}

    /**
     * Returns ReflectionReference if array element is a reference, null otherwise
     * @param array $array The array which contains the potential reference.
     * @param int|string $key The key; either an integer or a string.
     * @return ReflectionReference|null Returns a ReflectionReference instance if $array[$key] is a reference, or null otherwise.
     * @throws \TypeError If array is not an array, or key is not an integer or string, a TypeError is thrown.
     * @throws \ReflectionException If $array[$key] does not exist, a ReflectionException is thrown.
     */
    public static function fromArrayElement(
        array $array,
        string|int $key
    ): ?ReflectionReference {}

    /**
     * Returns unique identifier for the reference. The return value format is unspecified
     * @return int|string Returns an integer or string of unspecified format.
     */
    public function getId(): string {}

    /**
     * ReflectionReference cannot be cloned
     * @return void
     */
    private function __clone(): void {}
}
